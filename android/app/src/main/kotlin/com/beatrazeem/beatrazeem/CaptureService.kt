package com.beatrazeem.beatrazeem

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.*
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.*

class CaptureService : Service() {
    companion object {
        @Volatile var emit: ((Any) -> Unit)? = null
        var ready: ((String?) -> Unit)? = null
        @Volatile private var activeMixer: KaraokeMixer? = null
        @Volatile private var levels = Triple(1.0, 1.0, .7)
        fun setKaraokeLevels(singer: Double, microphone: Double, music: Double) {
            levels = Triple(singer, microphone, music)
            activeMixer?.setLevels(singer, microphone, music)
        }
    }
    private var projection: MediaProjection? = null
    private var recorder: AudioRecord? = null
    private var worker: Thread? = null
    private var micWorker: Thread? = null
    private var microphone: AudioRecord? = null
    private var echoCancel: android.media.audiofx.AcousticEchoCanceler? = null
    private var mixer: KaraokeMixer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    @Volatile private var running = false
    private val main = Handler(Looper.getMainLooper())
    private fun captureBlockTime(record: AudioRecord, clock: CaptureSampleClock, firstFrame: Long, frames: Int, startedAt: Long): Long? {
        val stamp = AudioTimestamp()
        val valid = record.getTimestamp(stamp, AudioTimestamp.TIMEBASE_MONOTONIC) == AudioRecord.SUCCESS && stamp.nanoTime > 0 && stamp.framePosition >= 0
        val now = System.nanoTime()
        // Let the recorder establish a timestamp before publishing its first
        // block. Otherwise an initially delayed read biases the whole stream.
        // Timestamp-less drivers still start after a bounded warmup.
        if (!valid && !clock.initialized && now - startedAt < 150_000_000L) return null
        return clock.blockStart(firstFrame, frames, now,
            if (valid) stamp.framePosition else null, if (valid) stamp.nanoTime else null)
    }
    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            if (running) emit?.invoke("Device audio sharing ended. Start it again to continue.")
            stopSelf()
        }
    }
    override fun onBind(intent: Intent?) = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (running) return START_NOT_STICKY
        try {
            if (Build.VERSION.SDK_INT < 29 || intent == null) error("Android 10 or newer is required.")
            val karaoke = intent.getBooleanExtra("karaoke", false)
            val notifications = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            notifications.createNotificationChannel(NotificationChannel("sharing", "Audio sharing", NotificationManager.IMPORTANCE_LOW))
            val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = Notification.Builder(this, "sharing")
                .setContentTitle(if (karaoke) "Beatrazeem Karaoke · microphone is on" else "Beatrazeem is sharing device audio")
                .setContentText("Tap to return to your room and stop sharing.")
                .setSmallIcon(android.R.drawable.ic_media_play).setContentIntent(open).setOngoing(true).build()
            val microphoneType = if (karaoke && Build.VERSION.SDK_INT >= 30) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0
            startForeground(7301, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or microphoneType)
            @Suppress("DEPRECATION")
            val permission = intent.getParcelableExtra<Intent>("projection") ?: error("Missing sharing permission.")
            val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            projection = manager.getMediaProjection(intent.getIntExtra("resultCode", Activity.RESULT_CANCELED), permission)
            projection!!.registerCallback(projectionCallback, main)
            val configuration = AudioPlaybackCaptureConfiguration.Builder(projection!!)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .excludeUid(android.os.Process.myUid())
                .build()
            val channelMask = if (karaoke) AudioFormat.CHANNEL_IN_STEREO else AudioFormat.CHANNEL_IN_MONO
            val format = AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(48000).setChannelMask(channelMask).build()
            val minSize = AudioRecord.getMinBufferSize(48000, channelMask, AudioFormat.ENCODING_PCM_16BIT)
            recorder = AudioRecord.Builder().setAudioFormat(format)
                .setBufferSizeInBytes(maxOf(minSize * 4, 19200))
                .setAudioPlaybackCaptureConfig(configuration).build()
            check(recorder!!.state == AudioRecord.STATE_INITIALIZED) { "Could not start device audio capture." }
            wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Beatrazeem:AudioSharing")
                .apply { acquire(4 * 60 * 60 * 1000L) }
            if (karaoke) {
                mixer = KaraokeMixer().also { it.setLevels(levels.first, levels.second, levels.third) }
                activeMixer = mixer
                val micFormat = AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(48000).setChannelMask(AudioFormat.CHANNEL_IN_MONO).build()
                val micSize = AudioRecord.getMinBufferSize(48000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                microphone = AudioRecord.Builder().setAudioSource(MediaRecorder.AudioSource.MIC)
                    .setAudioFormat(micFormat).setBufferSizeInBytes(maxOf(micSize * 4, 19200)).build()
                check(microphone!!.state == AudioRecord.STATE_INITIALIZED) { "Could not open the Karaoke microphone." }
                val managerAudio = getSystemService(AUDIO_SERVICE) as AudioManager
                managerAudio.getDevices(AudioManager.GET_DEVICES_INPUTS)
                    .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }?.let { microphone!!.setPreferredDevice(it) }
                try {
                    if (android.media.audiofx.AcousticEchoCanceler.isAvailable()) {
                        echoCancel = android.media.audiofx.AcousticEchoCanceler.create(microphone!!.audioSessionId)
                        echoCancel?.enabled = true
                    }
                } catch (_: Exception) { }
                microphone!!.startRecording()
                check(microphone!!.recordingState == AudioRecord.RECORDSTATE_RECORDING) { "Android could not start the Karaoke microphone." }
            }
            running = true
            if (karaoke) micWorker = Thread({
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_AUDIO)
                val bytes = ByteArray(960) // 10ms mic blocks avoid gaps at music-block boundaries.
                var fill = 0
                var micFrames = 0L
                val micClock = CaptureSampleClock()
                val startedAt = System.nanoTime()
                while (running) {
                    val read = microphone?.read(bytes, fill, bytes.size - fill, AudioRecord.READ_BLOCKING) ?: break
                    if (read <= 0) {
                        if (running) { emit?.invoke("Karaoke microphone stopped. Restart Karaoke."); main.post { stopSelf() } }
                        break
                    }
                    fill += read
                    if (fill == bytes.size) {
                        val start = captureBlockTime(microphone!!, micClock, micFrames, 480, startedAt)
                        if (start != null) mixer?.addVoice(bytes, start)
                        micFrames += 480
                        fill = 0
                    }
                }
            }, "BeatrazeemKaraokeMic").apply { start() }
            recorder!!.startRecording()
            check(recorder!!.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                "Android did not start device audio capture. Stop other recorders and try again."
            }
            worker = Thread({
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_AUDIO)
                val buffer = ByteArray(if (karaoke) 3840 else 1920)
                var filled = 0
                var capturedFrames = 0L
                val captureClock = CaptureSampleClock()
                val startedAt = System.nanoTime()
                while (running) {
                    val count = recorder?.read(buffer, filled, buffer.size - filled, AudioRecord.READ_BLOCKING) ?: break
                    if (count > 0) {
                        filled += count
                        if (filled < buffer.size) continue
                        // Use Android's recorder position/time so delayed reads
                        // cannot turn buffered old samples into newly captured audio.
                        val capturedAt = captureBlockTime(recorder!!, captureClock, capturedFrames, 960, startedAt)
                        capturedFrames += 960
                        filled = 0
                        if (capturedAt == null) continue
                        val karaokeMixer = mixer
                        val pcm = if (karaokeMixer != null) {
                            val waitUntil = System.nanoTime() + 30_000_000L
                            while (running && !karaokeMixer.voiceThrough(capturedAt + 20_000_000L) && System.nanoTime() < waitUntil) Thread.sleep(1)
                            karaokeMixer.mix(buffer, capturedAt)
                        } else buffer.copyOf()
                        if (running) emit?.invoke(mapOf("pcm" to pcm, "capturedAtNanos" to capturedAt))
                    }
                    else if (running) {
                        emit?.invoke("Audio capture stopped. Return to Beatrazeem to restart it.")
                        main.post { stopSelf() }; break
                    }
                }
            }, "BeatrazeemAudio").apply { start() }
            ready?.invoke(null); ready = null
        } catch (error: Exception) {
            ready?.invoke(error.message ?: "Could not share device audio."); ready = null
            stopSelf()
        }
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        running = false
        try { recorder?.stop() } catch (_: Exception) { }
        try { microphone?.stop() } catch (_: Exception) { }
        micWorker?.join(1000); micWorker = null
        echoCancel?.release(); echoCancel = null
        microphone?.release(); microphone = null
        if (activeMixer === mixer) activeMixer = null
        mixer?.clear(); mixer = null
        worker?.join(1000); worker = null
        recorder?.release(); recorder = null
        projection?.unregisterCallback(projectionCallback)
        projection?.stop(); projection = null
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
