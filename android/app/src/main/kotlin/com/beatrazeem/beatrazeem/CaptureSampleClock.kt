package com.beatrazeem.beatrazeem

import java.util.ArrayDeque

/** A continuous sample clock, gently disciplined by recorder timestamps. */
internal class CaptureSampleClock {
    private var origin: Double? = null
    private var previousFrame: Long? = null
    private var lastStampFrame = -1L
    private var lastStampTime = 0L
    private val origins = ArrayDeque<Double>()
    val initialized: Boolean get() = origin != null

    fun blockStart(firstFrame: Long, frames: Int, readAt: Long, stampFrame: Long? = null, stampTime: Long? = null): Long {
        require(firstFrame >= 0 && frames > 0)
        val period = 1_000_000_000.0 / 48000
        val fallbackOrigin = readAt - (firstFrame + frames) * period
        if (stampFrame != null && stampTime != null && stampFrame > lastStampFrame && stampTime > lastStampTime) {
            val measured = stampTime - stampFrame * period
            val start = measured + firstFrame * period
            if (start <= readAt + 20_000_000 && start >= readAt - 5_000_000_000L) {
                origins.addLast(measured)
                while (origins.size > 21) origins.removeFirst()
                lastStampFrame = stampFrame
                lastStampTime = stampTime
            }
        }
        val target = if (origins.isEmpty()) null else origins.sorted()[origins.size / 2]
        val current = origin
        if (current == null) {
            origin = target ?: fallbackOrigin
        } else if (target != null) {
            // A new AudioRecord observation is not a new audio block boundary.
            // Median filtering rejects outliers; a 0.2% rate limit tracks hardware
            // drift without creating gaps/overlaps or nearly duplicate times.
            val elapsed = (firstFrame - (previousFrame ?: firstFrame)).coerceAtLeast(0) * period
            val correction = ((target - current) * .05).coerceIn(-elapsed * .002, elapsed * .002)
            origin = current + correction
        }
        // Preserve backlog age. A delayed read must not move earlier samples
        // into the future just because the capture worker woke up late.
        previousFrame = firstFrame
        return (origin!! + firstFrame * period).toLong()
    }
}
