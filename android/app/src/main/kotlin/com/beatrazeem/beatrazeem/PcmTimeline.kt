package com.beatrazeem.beatrazeem

import java.util.ArrayDeque
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.roundToInt

/** Pure sample-time queue. Arrival time never determines when a packet is heard. */
internal class PcmTimeline(private val capacity: Int = 32) {
    companion object {
        const val RATE = 48_000
        const val SAMPLE_NS = 1_000_000_000.0 / RATE
    }

    private data class Packet(val sequence: Long, val start: Long, val samples: ShortArray, val capturedAt: Long?, val roomStart: Long) {
        val duration = samples.size * SAMPLE_NS
        var end = start + duration
        var captureDuration = duration
        var roomDuration = duration
        var committed = false

        fun join(next: Packet) {
            // Adjacent samples remain continuous when either clock is corrected.
            // Only bridge small corrections and consecutive sequences: a lost
            // packet or a real capture gap must never stretch/replay old sound.
            // Once any samples have been written, changing their time mapping
            // would skip/repeat samples at the next render quantum.
            if (committed || next.sequence != sequence + 1 ||
                abs(next.start - (start + duration)) > minOf(2_000_000.0, duration * .1)) return
            end = next.start.toDouble()
            if (capturedAt != null && next.capturedAt != null && next.capturedAt > capturedAt) {
                captureDuration = (next.capturedAt - capturedAt).toDouble()
            }
            roomDuration = (next.roomStart - roomStart).toDouble()
        }
    }

    private val packets = ArrayDeque<Packet>()
    private var lastSequence = -1L
    private var renderedUntil = Double.NEGATIVE_INFINITY
    var latePackets = 0
        private set
    val size: Int get() = packets.size
    data class RenderedSample(val outputIndex: Int, val capturedAt: Double?, val roomDeadline: Double)
    var lastRendered: RenderedSample? = null
        private set

    fun add(bytes: ByteArray, start: Long, sequence: Long, capturedAt: Long? = null, roomStart: Long = start): Boolean {
        if (bytes.isEmpty() || bytes.size % 2 != 0 || bytes.size > RATE * 2 || sequence < 0) return false
        if (sequence <= lastSequence) return false
        lastSequence = sequence
        val end = start + (bytes.size / 2) * SAMPLE_NS
        if (end <= renderedUntil) {
            latePackets++
            return false
        }
        if (start < renderedUntil) latePackets++ // A useful remainder can still be played.
        val samples = ShortArray(bytes.size / 2) { i ->
            ((bytes[i * 2].toInt() and 255) or (bytes[i * 2 + 1].toInt() shl 8)).toShort()
        }
        // Ordered WebSocket delivery is required. A clock correction can slightly
        // change spacing; an obsolete target must not move the queue backwards.
        if (packets.isNotEmpty() && start < packets.last.start) return false
        val packet = Packet(sequence, start, samples, capturedAt, roomStart)
        packets.peekLast()?.join(packet)
        while (packets.size >= capacity) {
            packets.removeFirst()
            latePackets++
        }
        packets.addLast(packet)
        return true
    }

    fun render(startNanos: Double, stepNanos: Double, count: Int): ByteArray {
        require(count > 0 && stepNanos > 0)
        lastRendered = null
        while (packets.isNotEmpty() && packets.first.end <= startNanos) packets.removeFirst()
        val available = packets.toList()
        var index = 0
        val output = ByteArray(count * 2)
        var lastIndex = -1
        var lastCapture = Double.NaN
        var lastRoomDeadline = 0.0
        for (i in 0 until count) {
            val time = startNanos + i * stepNanos
            while (index < available.size && available[index].end <= time) index++
            if (index >= available.size) continue
            val packet = available[index]
            if (time < packet.start) continue // Real timeline gaps become silence, never backlog.
            packet.committed = true
            val fraction = (time - packet.start) / (packet.end - packet.start)
            val position = fraction * packet.samples.size
            val sampleIndex = floor(position).toInt().coerceIn(0, packet.samples.lastIndex)
            val a = packet.samples[sampleIndex].toInt()
            val next = if (sampleIndex < packet.samples.lastIndex) {
                packet.samples[sampleIndex + 1].toInt()
            } else {
                val following = available.getOrNull(index + 1)
                if (following != null && following.sequence == packet.sequence + 1 &&
                    abs(following.start - packet.end) < SAMPLE_NS * .5) {
                    following.samples[0].toInt()
                } else a
            }
            val value = (a + (next - a) * (position - sampleIndex).coerceIn(0.0, 1.0))
                .roundToInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            output[i * 2] = value.toByte()
            output[i * 2 + 1] = (value shr 8).toByte()
            lastIndex = i
            lastCapture = if (packet.capturedAt != null) packet.capturedAt + fraction * packet.captureDuration else Double.NaN
            lastRoomDeadline = packet.roomStart + fraction * packet.roomDuration
        }
        if (lastIndex >= 0) lastRendered = RenderedSample(lastIndex, if (lastCapture.isNaN()) null else lastCapture, lastRoomDeadline)
        renderedUntil = startNanos + count * stepNanos
        while (packets.isNotEmpty() && packets.first.end <= renderedUntil) packets.removeFirst()
        return output
    }

    fun clear() {
        packets.clear()
        lastSequence = -1L
        renderedUntil = Double.NEGATIVE_INFINITY
        latePackets = 0
        lastRendered = null
    }
}

/** Relates an uninterrupted output sample cursor to presentation time. */
internal class OutputTimeline {
    data class Block(val start: Double, val step: Double, val reset: Boolean)
    private var next: Double? = null
    var errorNanos = 0.0
        private set
    var resyncs = 0
        private set

    fun nextBlock(predictedNanos: Double, count: Int, samplePeriod: Double = PcmTimeline.SAMPLE_NS, discontinuity: Boolean = false): Block {
        val previous = next
        errorNanos = if (previous == null) 0.0 else predictedNanos - previous
        // Output-route changes and underruns must not leave us replaying stale audio.
        val reset = previous == null || discontinuity || abs(errorNanos) > 40_000_000.0
        val start = if (reset) predictedNanos else previous!!
        if (reset && previous != null) resyncs++
        // Correct small errors over about half a second, limited to 1% resampling.
        // This avoids overlaps/gaps at every network packet boundary.
        val correction = if (reset) 0.0 else
            (errorNanos / (PcmTimeline.RATE * .5)).coerceIn(-samplePeriod * .01, samplePeriod * .01)
        val step = samplePeriod + correction
        next = start + count * step
        return Block(start, step, reset)
    }

    fun reset() {
        next = null
        errorNanos = 0.0
        resyncs = 0
    }
}

/** A measured speaker clock; nominal 48kHz alone drifts on independent phones. */
internal class PresentationClock {
    private var previousFrame = -1L
    private var previousTime = 0L
    private var anchorFrame = 0L
    private var anchorTime = 0L
    private var locked = false
    private data class Point(val frame: Long, val time: Long)
    private val history = ArrayDeque<Point>()
    var samplePeriod = PcmTimeline.SAMPLE_NS
        private set

    fun observe(frame: Long, time: Long, now: Long, written: Long) {
        if (frame < 0 || frame > written || time <= 0 || abs(time - now) > 2_000_000_000L) return
        if (frame <= previousFrame || time <= previousTime) return
        if (previousFrame >= 0) {
            val period = (time - previousTime).toDouble() / (frame - previousFrame)
            if (period in PcmTimeline.SAMPLE_NS * .98..PcmTimeline.SAMPLE_NS * 1.02) {
                history.addLast(Point(frame, time))
                while (history.size > 32 || (history.size > 2 && time - history.first.time > 20_000_000_000L)) history.removeFirst()
                val first = history.first
                // Fit a multi-second window. Adjacent noisy Android timestamps
                // must not keep speeding up and slowing down each phone.
                if (time - first.time >= 5_000_000_000L) {
                    val meanX = history.map { (it.frame - first.frame).toDouble() }.average()
                    val meanY = history.map { (it.time - first.time).toDouble() }.average()
                    var covariance = 0.0; var variance = 0.0
                    for (point in history) {
                        val x = point.frame - first.frame - meanX
                        covariance += x * (point.time - first.time - meanY)
                        variance += x * x
                    }
                    if (variance > 0) samplePeriod = (covariance / variance).coerceIn(PcmTimeline.SAMPLE_NS * .998, PcmTimeline.SAMPLE_NS * 1.002)
                    anchorTime = (first.time + meanY + (frame - first.frame - meanX) * samplePeriod).toLong()
                } else {
                    anchorTime = time
                }
                anchorFrame = frame
                locked = true
            }
        }
        previousFrame = frame
        previousTime = time
    }

    fun ready(now: Long) = locked && now - anchorTime < 2_000_000_000L
    fun presentation(frame: Long) = anchorTime + (frame - anchorFrame) * samplePeriod
    fun reset() {
        previousFrame = -1L; previousTime = 0L
        anchorFrame = 0L; anchorTime = 0L; locked = false
        samplePeriod = PcmTimeline.SAMPLE_NS
        history.clear()
    }
}

internal data class PlaybackDelay(val delayMs: Double?, val offsetMs: Double) {
    companion object {
        fun estimate(sample: PcmTimeline.RenderedSample, blockPresentation: Double, samplePeriod: Double): PlaybackDelay {
            val presentedAt = blockPresentation + sample.outputIndex * samplePeriod
            return PlaybackDelay(sample.capturedAt?.let { (presentedAt - it) / 1_000_000.0 },
                (presentedAt - sample.roomDeadline) / 1_000_000.0)
        }
    }
}
