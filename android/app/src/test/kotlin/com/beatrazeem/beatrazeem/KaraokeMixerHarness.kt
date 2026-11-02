package com.beatrazeem.beatrazeem

import kotlin.math.*

private fun stereoTone(hz: Double, amp: Int = 8000, opposite: Boolean = false): ByteArray {
    val pcm = ByteArray(48000 * 4)
    for (i in 0 until 48000) {
        val v = (sin(2 * PI * hz * i / 48000) * amp).roundToInt()
        val r = if (opposite) -v else v
        pcm[i*4]=v.toByte(); pcm[i*4+1]=(v shr 8).toByte()
        pcm[i*4+2]=r.toByte(); pcm[i*4+3]=(r shr 8).toByte()
    }
    return pcm
}
private fun value(p: ByteArray, i: Int) = ((p[i*2].toInt() and 255) or (p[i*2+1].toInt() shl 8)).toShort().toInt()
private fun rms(p: ByteArray): Double = sqrt((24000 until p.size/2).sumOf { value(p,it).toDouble().pow(2) } / (p.size/2-24000))
fun main() {
    val tone = stereoTone(1000.0)
    fun output(gain: Double) = KaraokeMixer().apply { setLevels(gain, 0.0, 1.0) }.mix(tone, 0)
    val original = rms(output(1.0)); val reduced = rms(output(0.0)); val raised = rms(output(1.5))
    check(abs(original-8000/sqrt(2.0)) < 3) { "Original setting changes the song" }
    check(reduced < original * .5) { "Center-band reduction failed: $reduced vs $original" }
    check(raised > original * 1.2) { "Singer emphasis failed" }
    val bass = KaraokeMixer().apply { setLevels(0.0,0.0,1.0) }.mix(stereoTone(40.0),0)
    check(rms(bass) > original * .8) { "Low backing frequencies were lost" }
    val side = KaraokeMixer().apply { setLevels(0.0,0.0,1.0) }.mix(stereoTone(1000.0, opposite=true),0)
    check(rms(side) > original * .7) { "Stereo side information was lost" }
    val mic = ByteArray(96000)
    for(i in 0 until mic.size/2) {mic[i*2]=0x88.toByte();mic[i*2+1]=0x13} // 5000
    val mixer = KaraokeMixer().apply {setLevels(0.0,1.0,0.0);addVoice(mic,0)}
    val voice = mixer.mix(ByteArray(192000),0)
    check(abs(rms(voice)-5000) < 2) { "Singer control changed live microphone" }
    mixer.setLevels(0.0,0.0,0.0);mixer.addVoice(mic,1_000_000_000)
    check(rms(mixer.mix(ByteArray(192000),1_000_000_000)) < 2) { "Microphone mute failed" }
    check(mixer.mix(ByteArray(19200),3_000_000_000).all { it == 0.toByte() }) { "Old microphone audio replayed" }
    val hot = KaraokeMixer().apply {setLevels(1.5,2.0,1.0);addVoice(mic,0)}.mix(stereoTone(1000.0,32000),0)
    check((0 until hot.size/2).all { abs(value(hot,it)) <= 32767 })
    val blocks = KaraokeMixer()
    val tenMs = mic.copyOf(960)
    for (i in 0 until 100) blocks.addVoice(tenMs, i * 10_000_000L)
    val boundary = blocks.mix(ByteArray(19200), 895_000_000L)
    check((0 until boundary.size/2).all { value(boundary,it) == 5000 }) { "Mic block boundaries contain gaps" }
    mixer.clear()
    val shortBlocks = KaraokeMixer()
    for (i in 0 until 10) shortBlocks.addVoice(tenMs, i * 10_000_000L)
    repeat(5) { block ->
        val shared = shortBlocks.mix(ByteArray(3840), block * 20_000_000L)
        check(shared.size == 1920)
        check((0 until shared.size / 2).all { value(shared, it) == 5000 }) { "20ms Karaoke packets lost microphone samples" }
    }
    println("11 Karaoke checks passed: neutral, reduction, emphasis, bass, stereo sides, independent mic, mic mute, stale audio, peak limiting, mic block boundaries, 20ms mixed packets.")
}
