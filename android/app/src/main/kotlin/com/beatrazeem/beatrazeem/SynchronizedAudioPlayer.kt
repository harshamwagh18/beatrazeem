package com.beatrazeem.beatrazeem

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTimestamp
import android.media.AudioTrack
import android.os.Build
import android.os.Process
import kotlin.math.max

/**
 * One continuous media track per device. Packets are sampled against their
 * shared presentation deadlines, including Android's measured output pipeline.
 * A worker owns every AudioTrack operation; UI and network calls never block on
 * a hardware write. No recording or source-app volume is modified here.
 */
class SynchronizedAudioPlayer(private val onError: (String) -> Unit = {}) {
    companion object {
        private const val BLOCK_FRAMES = 480 // 10ms render quantum, independent of network packets.
        private const val MAX_FUTURE_NS = 3_000_000_000L
        private const val WARM_POLL_NS = 50_000_000L
        private const val STABLE_POLL_NS = 1_000_000_000L
        private const val IDLE_NS = 3_000_000_000L
    }

    private val lock = Object()
    private val timeline = PcmTimeline()
    @Volatile private var closed = false
    @Volatile private var enabled = false
    @Volatile private var generation = 0L
    @Volatile private var requestedVolume = .75f
    private var worker: Thread? = null
    private var lastEnqueue = 0L
    @Volatile private var running = false
    @Volatile private var timestampReady = false
    @Volatile private var bufferedMs = 0
    @Volatile private var syncErrorMs = 0.0
    @Volatile private var underruns = 0
    @Volatile private var resyncs = 0
    @Volatile private var lastDelay: PlaybackDelay? = null
    @Volatile private var lastDelayAt = 0L
    @Volatile private var lastDelayMeasured = false

    fun initialize() = synchronized(lock) {
        check(!closed) { "Audio output has been disposed." }
        enabled = true
        lastEnqueue = System.nanoTime()
        ensureWorker()
        lock.notifyAll()
    }

    fun enqueue(pcm: ByteArray, playAtNanos: Long, sequence: Long, capturedAtNanos: Long? = null, roomPlayAtNanos: Long = playAtNanos) = synchronized(lock) {
        if (closed) return@synchronized
        val now = System.nanoTime()
        if (playAtNanos > now + MAX_FUTURE_NS || playAtNanos < now - MAX_FUTURE_NS) return@synchronized
        if (!timeline.add(pcm, playAtNanos, sequence, capturedAtNanos, roomPlayAtNanos)) return@synchronized
        lastEnqueue = now
        enabled = true
        ensureWorker()
        lock.notifyAll()
    }

    fun setVolume(value: Float) { requestedVolume = value.coerceIn(0f, 1f) }

    fun stop() = synchronized(lock) {
        generation++
        enabled = false
        timeline.clear()
        timestampReady = false
        bufferedMs = 0
        syncErrorMs = 0.0
        underruns = 0
        resyncs = 0
        lastDelay = null
        lastDelayAt = 0L
        lastDelayMeasured = false
        lock.notifyAll()
        // The non-blocking worker observes this within its next 2ms wait and
        // pauses/flushes the native track. No UI-thread join or blocking write.
    }

    fun close() = synchronized(lock) {
        if (closed) return@synchronized
        stop()
        closed = true
        lock.notifyAll()
        worker?.interrupt()
    }

    fun status(): Map<String, Any?> = synchronized(lock) {
        val fresh = running && timestampReady && lastDelayMeasured && System.nanoTime() - lastDelayAt < 1_500_000_000L
        mapOf(
            "running" to running,
            "timestampReady" to timestampReady,
            "queuedPackets" to timeline.size,
            "bufferedMs" to bufferedMs,
            "lateFrames" to timeline.latePackets,
            "syncErrorMs" to syncErrorMs,
            "underruns" to underruns,
            "resyncs" to resyncs,
            "estimatedDelayMs" to if (fresh) lastDelay?.delayMs else null,
            "timingOffsetMs" to if (fresh) lastDelay?.offsetMs else null,
            "fresh" to fresh,
        )
    }

    private fun ensureWorker() {
        if (worker != null) return
        worker = Thread({ runWorker() }, "Beatrazeem-playback").apply {
            isDaemon = true
            start()
        }
    }

    private fun runWorker() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
        while (!closed) {
            val currentGeneration = try {
                synchronized(lock) {
                    while (!closed && !enabled) lock.wait()
                    generation
                }
            } catch (_: InterruptedException) {
                break
            }
            if (closed) break
            var track: AudioTrack? = null
            try {
                track = createTrack()
                if (!active(currentGeneration)) continue
                running = true
                playLoop(track, currentGeneration)
            } catch (_: InterruptedException) {
                if (!closed) Thread.currentThread().interrupt()
                break
            } catch (error: Exception) {
                synchronized(lock) {
                    if (generation == currentGeneration) {
                        enabled = false
                        timeline.clear()
                    }
                }
                if (!closed) onError("Audio output failed: ${error.message ?: error.javaClass.simpleName}")
            } finally {
                running = false
                timestampReady = false
                bufferedMs = 0
                if (track != null) {
                    try { track.pause() } catch (_: Exception) { }
                    try { track.flush() } catch (_: Exception) { }
                    track.release()
                }
            }
        }
    }

    private fun active(expected: Long) = !closed && enabled && generation == expected

    private fun createTrack(): AudioTrack {
        val minimum = AudioTrack.getMinBufferSize(
            PcmTimeline.RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT,
        )
        check(minimum > 0) { "48 kHz mono playback is unavailable on this device." }
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        // Never recapture our own monitoring output into an app-audio room.
        if (Build.VERSION.SDK_INT >= 29) {
            attributes.setAllowedCapturePolicy(AudioAttributes.ALLOW_CAPTURE_BY_NONE)
        }
        val builder = AudioTrack.Builder()
            .setAudioAttributes(attributes.build())
            .setAudioFormat(AudioFormat.Builder()
                .setSampleRate(PcmTimeline.RATE)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(max(minimum * 2, BLOCK_FRAMES * 2 * 4))
        if (Build.VERSION.SDK_INT >= 26) builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
        val track = builder.build()
        if (track.state != AudioTrack.STATE_INITIALIZED) {
            track.release()
            error("Android could not initialize the media output.")
        }
        // Keep enough allocated capacity for recovery, but do not prequeue a
        // full large hardware buffer when a smaller effective buffer works.
        track.setBufferSizeInFrames(max(BLOCK_FRAMES * 4, minimum / 2))
        return track
    }

    private fun playLoop(track: AudioTrack, expected: Long) {
        var writtenFrames = 0L
        var headWraps = 0L
        var lastHead = 0L
        var nextTimestampPoll = 0L
        var nextRouteCheck = 0L
        var routeId = -1
        var observedUnderruns = 0
        var outputDiscontinuity = false
        var appliedVolume = requestedVolume
        val timestamp = AudioTimestamp()
        val outputTimeline = OutputTimeline()
        val speakerClock = PresentationClock()
        val capacity = track.bufferSizeInFrames
        val leadFrames = capacity.coerceAtLeast(BLOCK_FRAMES)
        val prime = ByteArray(capacity * 2)
        var offset = 0
        // Prime while stopped so Android's streaming start threshold is met.
        while (offset < prime.size && active(expected)) {
            val count = track.write(prime, offset, prime.size - offset, AudioTrack.WRITE_NON_BLOCKING)
            if (count < 0) error("Cannot prime output ($count).")
            if (count == 0) break
            offset += count
        }
        writtenFrames += offset / 2
        if (!active(expected)) return
        track.setVolume(appliedVolume)
        track.play()

        while (active(expected)) {
            val now = System.nanoTime()
            val rawHead = track.playbackHeadPosition.toLong() and 0xffffffffL
            if (rawHead < lastHead && lastHead - rawHead > 0x80000000L) headWraps += 1L shl 32
            lastHead = rawHead
            val head = headWraps + rawHead
            val queued = (writtenFrames - head).coerceAtLeast(0)
            bufferedMs = (queued * 1000 / PcmTimeline.RATE).toInt()

            // Check every render cycle: waiting 500ms after an underrun leaves
            // stale samples playing against the previous hardware timebase.
            val nextUnderruns = track.underrunCount
            if (nextUnderruns > observedUnderruns) outputDiscontinuity = true
            observedUnderruns = nextUnderruns
            underruns = nextUnderruns
            if (now >= nextRouteCheck) {
                nextRouteCheck = now + 500_000_000L
                val nextRoute = track.routedDevice?.id ?: -1
                if (routeId != -1 && nextRoute != routeId) outputDiscontinuity = true
                routeId = nextRoute
            }
            if (outputDiscontinuity) {
                timestampReady = false
                lastDelayMeasured = false
                speakerClock.reset()
                nextTimestampPoll = 0
            }
            if (now >= nextTimestampPoll) {
                nextTimestampPoll = now + if (timestampReady) STABLE_POLL_NS else WARM_POLL_NS
                if (track.getTimestamp(timestamp)) {
                    // Timestamp frames also wrap at 32 bits. Map to the nearest
                    // playback-head epoch; its point may be committed in advance.
                    val raw = timestamp.framePosition and 0xffffffffL
                    var frame = headWraps + raw
                    if (frame - head > 0x80000000L) frame -= 1L shl 32
                    if (head - frame > 0x80000000L) frame += 1L shl 32
                    speakerClock.observe(frame, timestamp.nanoTime, now, writtenFrames)
                }
            }
            timestampReady = speakerClock.ready(now)
            if (appliedVolume != requestedVolume) {
                appliedVolume = requestedVolume
                track.setVolume(appliedVolume)
            }
            if (queued >= leadFrames) {
                Thread.sleep(2)
                continue
            }
            synchronized(lock) {
                if (timeline.size == 0 && now - lastEnqueue > IDLE_NS) enabled = false
            }
            if (!active(expected)) return
            val predicted = if (timestampReady) {
                speakerClock.presentation(writtenFrames)
            } else {
                // Playback-head fallback does not measure downstream speaker
                // latency. status() exposes this instead of claiming exact sync.
                now + queued * PcmTimeline.SAMPLE_NS
            }
            val block = outputTimeline.nextBlock(predicted, BLOCK_FRAMES,
                if (timestampReady) speakerClock.samplePeriod else PcmTimeline.SAMPLE_NS,
                discontinuity = outputDiscontinuity)
            outputDiscontinuity = false
            syncErrorMs = outputTimeline.errorNanos / 1_000_000.0
            resyncs = outputTimeline.resyncs
            val rendered = synchronized(lock) {
                if (!active(expected)) return
                val pcm = timeline.render(block.start, block.step, BLOCK_FRAMES)
                Pair(pcm, timeline.lastRendered)
            }
            val pcm = rendered.first
            var writtenBytes = 0
            while (writtenBytes < pcm.size && active(expected)) {
                val count = track.write(pcm, writtenBytes, pcm.size - writtenBytes, AudioTrack.WRITE_NON_BLOCKING)
                if (count < 0) error("Android rejected an audio write ($count).")
                if (count == 0) {
                    Thread.sleep(2)
                } else {
                    writtenBytes += count
                    writtenFrames += count / 2
                }
            }
            if (active(expected) && writtenBytes == pcm.size) {
                rendered.second?.let {
                    lastDelay = PlaybackDelay.estimate(it, predicted,
                        if (timestampReady) speakerClock.samplePeriod else PcmTimeline.SAMPLE_NS)
                    lastDelayAt = System.nanoTime()
                    lastDelayMeasured = timestampReady && track.underrunCount == observedUnderruns
                }
            }
        }
    }
}
