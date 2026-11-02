package com.beatrazeem.beatrazeem

import kotlin.math.*

/** Stereo center-band reduction, not source separation. All output is mono PCM16. */
class KaraokeMixer {
    private data class Voice(val pcm: ByteArray, val start: Long) {
        val end get() = start + pcm.size / 2 * 1_000_000_000L / RATE
    }
    companion object { const val RATE = 48000 }
    private val voices = ArrayDeque<Voice>()
    @Volatile private var singerTarget = 1.0
    @Volatile private var voiceTarget = 1.0
    @Volatile private var musicTarget = .7
    private var singer = 1.0
    private var voice = 1.0
    private var music = .7
    private var lowMid = 0.0
    private var highMid = 0.0
    private var lowSide = 0.0
    private var highSide = 0.0
    private val lowAlpha = 1 - exp(-2 * PI * 200 / RATE)
    private val highAlpha = 1 - exp(-2 * PI * 4500 / RATE)
    private val gainAlpha = 1 - exp(-1.0 / (RATE * .02))

    fun setLevels(singer: Double, microphone: Double, backing: Double) {
        singerTarget = if (singer.isFinite()) singer.coerceIn(0.0, 1.5) else 1.0
        voiceTarget = if (microphone.isFinite()) microphone.coerceIn(0.0, 2.0) else 1.0
        musicTarget = if (backing.isFinite()) backing.coerceIn(0.0, 1.0) else .7
    }
    @Synchronized fun addVoice(pcm: ByteArray, start: Long) {
        if (pcm.isEmpty() || pcm.size % 2 != 0) return
        if (voices.lastOrNull()?.start?.let { start <= it } == true) return
        voices.addLast(Voice(pcm.copyOf(), start))
        while (voices.size > 64) voices.removeFirst()
    }
    @Synchronized fun voiceThrough(time: Long) = voices.lastOrNull()?.end?.let { it >= time } ?: false
    @Synchronized fun clear() { voices.clear(); lowMid=0.0; highMid=0.0; lowSide=0.0; highSide=0.0 }

    @Synchronized fun mix(stereo: ByteArray, start: Long): ByteArray {
        require(stereo.size % 4 == 0)
        while (voices.isNotEmpty() && voices.first().end <= start) voices.removeFirst()
        val packets = voices.toList()
        var packetIndex = 0
        val out = ByteArray(stereo.size / 2)
        for (i in 0 until stereo.size / 4) {
            singer += (singerTarget - singer) * gainAlpha
            voice += (voiceTarget - voice) * gainAlpha
            music += (musicTarget - music) * gainAlpha
            val left = sample(stereo, i * 4).toDouble()
            val right = sample(stereo, i * 4 + 2).toDouble()
            val mid = (left + right) * .5
            val side = (left - right) * .5
            lowMid += lowAlpha * (mid - lowMid); highMid += highAlpha * (mid - highMid)
            lowSide += lowAlpha * (side - lowSide); highSide += highAlpha * (side - highSide)
            // Preserve bass/treble; replace the reduced center band with the side band.
            val backing = mid + (singer - 1) * (highMid - lowMid) +
                max(0.0, 1 - singer) * (highSide - lowSide)
            val time = start + i * 1_000_000_000L / RATE
            while (packetIndex < packets.size && packets[packetIndex].end <= time) packetIndex++
            val packet = packets.getOrNull(packetIndex)
            val mic = if (packet != null && time >= packet.start) {
                val index = ((time - packet.start) * RATE / 1_000_000_000L).toInt() * 2
                if (index + 1 < packet.pcm.size) sample(packet.pcm, index).toDouble() else 0.0
            } else 0.0
            val sum = backing * music + mic * voice
            // A soft knee contains peaks when microphone and music overlap.
            val limited = if (abs(sum) > 28000) sign(sum) *
                (28000 + 4767 * tanh((abs(sum) - 28000) / 4767)) else sum
            val value = limited.roundToInt().coerceIn(-32768, 32767)
            out[i * 2] = value.toByte(); out[i * 2 + 1] = (value shr 8).toByte()
        }
        return out
    }
    private fun sample(bytes: ByteArray, at: Int): Int =
        ((bytes[at].toInt() and 255) or (bytes[at + 1].toInt() shl 8)).toShort().toInt()
}
