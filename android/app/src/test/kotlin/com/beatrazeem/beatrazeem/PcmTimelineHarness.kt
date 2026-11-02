package com.beatrazeem.beatrazeem

/** Standalone JVM regression checks; no Android device or test dependency needed. */
fun main() {
    fun pcm(vararg values: Int): ByteArray = ByteArray(values.size * 2).also { bytes ->
        values.forEachIndexed { i, v -> bytes[i * 2] = v.toByte(); bytes[i * 2 + 1] = (v shr 8).toByte() }
    }
    fun decoded(bytes: ByteArray) = bytes.indices.step(2).map { i ->
        ((bytes[i].toInt() and 255) or (bytes[i + 1].toInt() shl 8)).toShort().toInt()
    }
    var checks = 0
    fun verify(name: String, test: () -> Unit) { test(); checks++; println("PASS $name") }
    val sample = PcmTimeline.SAMPLE_NS

    verify("adjacent packets stay contiguous across render blocks") {
        val queue = PcmTimeline()
        check(queue.add(pcm(100, 200, 300), 0L, 0))
        check(queue.add(pcm(400, 500, 600), 62_500L, 1))
        check(decoded(queue.render(0.0, sample, 2)) == listOf(100, 200))
        check(decoded(queue.render(2 * sample, sample, 4)) == listOf(300, 400, 500, 600))
        check(queue.size == 0)
    }
    verify("missing packet interval is silence rather than delayed backlog") {
        val queue = PcmTimeline()
        queue.add(pcm(100, 200, 300), 0L, 0)
        queue.add(pcm(700, 800, 900), 125_000L, 2)
        check(decoded(queue.render(0.0, sample, 9)) == listOf(100, 200, 300, 0, 0, 0, 700, 800, 900))
    }
    verify("late arrivals are trimmed or dropped against committed output") {
        val queue = PcmTimeline()
        queue.render(0.0, sample, 3)
        check(!queue.add(pcm(1, 2, 3), 0L, 0))
        check(queue.add(pcm(10, 20, 30, 40, 50, 60), 0L, 1))
        check(decoded(queue.render(3 * sample, sample, 3)) == listOf(40, 50, 60))
        check(queue.latePackets == 2)
    }
    verify("duplicate sequences are ignored and queue remains bounded") {
        val queue = PcmTimeline(capacity = 2)
        check(queue.add(pcm(1, 2, 3), 0, 0))
        check(!queue.add(pcm(1, 2, 3), 0, 0))
        check(queue.add(pcm(4, 5, 6), 62_500, 1))
        check(queue.add(pcm(7, 8, 9), 125_000, 2))
        check(queue.size == 2 && queue.latePackets == 1)
    }
    verify("reset accepts a new stream sequence without stale audio") {
        val queue = PcmTimeline()
        queue.add(pcm(99, 99, 99), 0, 47)
        queue.render(0.0, sample, 3)
        queue.clear()
        check(queue.add(pcm(-32768, 0, 32767), 0, 0))
        check(decoded(queue.render(0.0, sample, 3)) == listOf(-32768, 0, 32767))
        check(queue.latePackets == 0)
    }
    verify("linear interpolation crosses a packet boundary smoothly") {
        val queue = PcmTimeline()
        queue.add(pcm(100, 200, 300), 0, 0)
        queue.add(pcm(400, 500, 600), 62_500, 1)
        check(decoded(queue.render(sample * 2.5, sample, 2)) == listOf(350, 450))
    }
    verify("small output-clock error slews without resetting each packet") {
        val timeline = OutputTimeline()
        val first = timeline.nextBlock(1_000_000_000.0, 480)
        check(first.reset)
        var target = first.start + 480 * sample + 2_000_000.0
        repeat(200) {
            val block = timeline.nextBlock(target, 480)
            check(!block.reset)
            check(block.step in sample * .99..sample * 1.01)
            target += 480 * sample
        }
        check(kotlin.math.abs(timeline.errorNanos) < 50_000.0)
        check(timeline.resyncs == 0)
    }
    verify("large output discontinuity reanchors instead of retaining a lag") {
        val timeline = OutputTimeline()
        timeline.nextBlock(1_000_000_000.0, 480)
        val moved = timeline.nextBlock(1_300_000_000.0, 480)
        check(moved.reset && moved.start == 1_300_000_000.0)
        check(timeline.resyncs == 1)
    }
    verify("independent speaker clocks do not accumulate drift over ten minutes") {
        for (ppm in listOf(-800.0, 800.0)) {
            val clock = PresentationClock()
            val actualPeriod = sample * (1 + ppm / 1_000_000)
            val origin = 10_000_000_000L
            repeat(1200) { step ->
                val frame = step * 24000L
                val stamp = origin + (frame * actualPeriod).toLong()
                clock.observe(frame, stamp, stamp + 1_000_000, frame + 9600)
                if (step > 30) {
                    val predicted = clock.presentation(frame + 9600)
                    val actual = origin + (frame + 9600) * actualPeriod
                    check(kotlin.math.abs(predicted - actual) < 100_000)
                    check(clock.ready(stamp + 1_000_000))
                }
            }
        }
    }
    verify("frozen timestamps expire and route changes reset the speaker clock") {
        val clock = PresentationClock()
        clock.observe(0, 1_000_000_000, 1_000_000_000, 48000)
        clock.observe(24000, 1_500_000_000, 1_500_000_000, 48000)
        check(clock.ready(1_600_000_000))
        clock.observe(24000, 1_500_000_000, 3_600_000_000, 48000)
        check(!clock.ready(3_600_000_000))
        clock.reset()
        check(!clock.ready(1_600_000_000))
        check(clock.samplePeriod == sample)
    }
    verify("invalid speaker rates never establish an output clock") {
        val clock = PresentationClock()
        clock.observe(0, 1_000_000_000, 1_000_000_000, 48000)
        clock.observe(24000, 1_100_000_000, 1_100_000_000, 48000)
        check(!clock.ready(1_100_000_000))
    }
    verify("recorder timestamps preserve old audio age after a delayed read") {
        val clock = CaptureSampleClock()
        check(clock.blockStart(0, 4800, 1_110_000_000, 4800, 1_100_000_000) == 1_000_000_000L)
        check(clock.blockStart(4800, 4800, 1_550_000_000, 24000, 1_500_000_000) == 1_100_000_000L)
    }
    verify("capture fallback uses sample position rather than delayed read arrivals") {
        val clock = CaptureSampleClock()
        check(clock.blockStart(0, 4800, 1_100_000_000) == 1_000_000_000L)
        check(clock.blockStart(4800, 4800, 1_550_000_000) == 1_100_000_000L)
        check(clock.blockStart(9600, 4800, 1_551_000_000) == 1_200_000_000L)
    }
    verify("delay readings follow rendered capture samples and include manual timing") {
        val queue = PcmTimeline()
        val bytes = ByteArray(960)
        queue.add(bytes, 1_000_000_000, 0, 800_000_000, 970_000_000)
        queue.render(1_000_000_000.0, sample, 480)
        val delay = PlaybackDelay.estimate(queue.lastRendered!!, 1_005_000_000.0, sample)
        check(kotlin.math.abs(delay.delayMs!! - 205.0) < .001)
        check(kotlin.math.abs(delay.offsetMs - 35.0) < .001)
        queue.render(2_000_000_000.0, sample, 480)
        check(queue.lastRendered == null)
    }
    verify("legacy audio without capture timestamps never invents a delay value") {
        val queue = PcmTimeline()
        queue.add(ByteArray(960), 1_000_000_000, 0)
        queue.render(1_000_000_000.0, sample, 480)
        check(PlaybackDelay.estimate(queue.lastRendered!!, 1_000_000_000.0, sample).delayMs == null)
    }
    verify("timestamp jitter does not become repeated speaker speed changes") {
        val clock = PresentationClock()
        val actualPeriod = sample * 1.0002
        val origin = 10_000_000_000L
        repeat(180) { second ->
            val frame = second * 48000L
            val jitter = if (second % 2 == 0) 2_000_000L else -2_000_000L
            val actual = origin + (frame * actualPeriod).toLong()
            clock.observe(frame, actual + jitter, actual + 3_000_000, frame + 9600)
            if (second > 40) {
                check(kotlin.math.abs(clock.samplePeriod / actualPeriod - 1) < .0001)
                check(kotlin.math.abs(clock.presentation(frame + 9600) - (origin + (frame + 9600) * actualPeriod)) < 500_000)
            }
        }
    }
    verify("capture timestamp jitter cannot overlap or separate successive audio blocks") {
        val clock = CaptureSampleClock()
        val origin = 10_000_000_000L
        var previous = origin - 20_000_000
        repeat(400) { block ->
            val frame = block * 960L
            val jitter = when (block % 4) { 0 -> 0L; 1 -> 3_000_000L; 2 -> -30_000_000L; else -> 1_000_000L }
            val start = clock.blockStart(frame, 960, origin + frame * 1_000_000_000L / 48000 + 25_000_000,
                frame + 960, origin + (frame + 960) * 1_000_000_000L / 48000 + jitter)
            check(kotlin.math.abs(start - previous - 20_000_000) <= 40_001) { "Capture spacing ${start - previous} ns" }
            previous = start
        }
    }
    verify("small positive packet clock corrections contain no inserted silence") {
        val queue = PcmTimeline()
        queue.add(pcm(*IntArray(960) { 12000 }), 0, 0)
        queue.add(pcm(*IntArray(960) { 12000 }), 21_000_000, 1)
        check(decoded(queue.render(0.0, sample, 1968)).all { it == 12000 })
    }
    verify("small negative packet clock corrections preserve the next packet beginning") {
        val queue = PcmTimeline()
        queue.add(pcm(*IntArray(960) { it }), 0, 0)
        queue.add(pcm(*IntArray(960) { 960 + it }), 19_000_000, 1)
        check(decoded(queue.render(19_000_000.0, sample, 1)).single() == 960)
    }
    verify("known short output interruptions reanchor immediately") {
        val timeline = OutputTimeline()
        timeline.nextBlock(1_000_000_000.0, 480)
        val moved = timeline.nextBlock(1_035_000_000.0, 480, discontinuity = true)
        check(moved.reset && moved.start == 1_035_000_000.0)
        check(moved.step == sample && timeline.resyncs == 1)
        check(!timeline.nextBlock(1_045_000_000.0, 480).reset)
    }
    verify("packet interpolation never conceals missing audio or large discontinuities") {
        for ((sequence, nextStart) in listOf(2L to 21_000_000L, 1L to 30_000_000L)) {
            val queue = PcmTimeline()
            queue.add(pcm(*IntArray(960) { 12000 }), 0, 0)
            queue.add(pcm(*IntArray(960) { 12000 }), nextStart, sequence)
            check(decoded(queue.render(20_000_000.0, sample, 48)).all { it == 0 })
        }
    }
    verify("joined packet delay metadata follows the actual sample interpolation") {
        val queue = PcmTimeline()
        queue.add(pcm(*IntArray(960) { 12000 }), 1_000_000_000, 0, 800_000_000, 995_000_000)
        queue.add(pcm(*IntArray(960) { 12000 }), 1_021_000_000, 1, 820_000_000, 1_016_000_000)
        queue.render(1_010_500_000.0, sample, 1)
        val delay = PlaybackDelay.estimate(queue.lastRendered!!, 1_010_500_000.0, sample)
        check(kotlin.math.abs(delay.delayMs!! - 200.5) < .001)
        check(kotlin.math.abs(delay.offsetMs - 5) < .001)
    }
    verify("jittered capture and clock corrections play continuously for two minutes") {
        val clock = CaptureSampleClock()
        val queue = PcmTimeline()
        val origin = 10_000_000_000L
        val actualPeriod = sample * 1.0008
        val bytes = pcm(*IntArray(960) { 12000 })
        var renderAt: Double? = null
        var previous = 0L
        repeat(6000) { block ->
            val frame = block * 960L
            val actual = origin + (frame * actualPeriod).toLong()
            val noise = when (block % 7) { 0 -> -30_000_000L; 1 -> 3_000_000L; 2 -> -2_000_000L; else -> 0L }
            val start = clock.blockStart(frame, 960, actual + 25_000_000,
                frame + 960, origin + ((frame + 960) * actualPeriod).toLong() + if (block == 0) 0 else noise)
            if (block > 100) check(kotlin.math.abs(start - actual) < 2_000_000)
            if (block > 0) check(start - previous in 19_960_000L..20_040_001L)
            previous = start
            // Emulate the bounded per-packet room-clock correction as well as
            // capture-clock drift. Keep a normal 200ms network playout lead.
            val clockCorrection = if ((block / 25) % 2 == 0) 0L else 1_000_000L
            val playAt = start + 200_000_000L + clockCorrection
            check(queue.add(bytes, playAt, block.toLong(), start))
            if (renderAt == null) renderAt = playAt.toDouble()
            while (renderAt!! + 10_000_000 <= playAt - 100_000_000) {
                check(decoded(queue.render(renderAt!!, sample, 480)).all { it == 12000 }) { "Audible gap at block $block" }
                renderAt = renderAt!! + 10_000_000
            }
            check(queue.latePackets == 0)
        }
    }
    verify("a late successor never retimes samples already partially rendered") {
        for (nextStart in listOf(19_000_000L, 21_000_000L)) {
            val queue = PcmTimeline()
            queue.add(pcm(*IntArray(960) { it * 10 }), 0, 0)
            check(decoded(queue.render(0.0, sample, 480)).last() == 4790)
            queue.add(pcm(*IntArray(960) { (it + 960) * 10 }), nextStart, 1)
            check(decoded(queue.render(10_000_000.0, sample, 1)).single() == 4800)
        }
    }
    verify("capture priming keeps frame positions after discarded startup blocks") {
        val clock = CaptureSampleClock()
        check(!clock.initialized)
        check(clock.blockStart(5760, 960, 1_180_000_000, 6720, 1_140_000_000) == 1_120_000_000L)
        check(clock.initialized)
        check(clock.blockStart(6720, 960, 1_181_000_000, 7680, 1_160_000_000) == 1_140_000_000L)
    }
    println("All $checks native timeline checks passed.")
}
