package com.beatrazeem.beatrazeem

import android.app.Activity
import android.content.Intent
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.projection.MediaProjectionManager
import android.media.projection.MediaProjectionConfig
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var output: SynchronizedAudioPlayer? = null
    private var pendingKaraoke = false
    private var pending: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())
    private val profileIo = Executors.newSingleThreadExecutor()
    private lateinit var localNetwork: LocalNetwork

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        localNetwork = LocalNetwork(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "beatrazeem/network")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "prepareListener" -> result.success(localNetwork.prepareListener())
                        "release" -> { localNetwork.release(); result.success(null) }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) { result.error("network", error.message, null) }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "beatrazeem/profile")
            .setMethodCallHandler { call, result ->
                if (call.method != "readUsername" && call.method != "saveUsername") {
                    result.notImplemented()
                } else {
                    profileIo.execute {
                        try {
                            val preferences = getSharedPreferences("com.beatrazeem.beatrazeem.profile", MODE_PRIVATE)
                            if (call.method == "readUsername") {
                                val name = preferences.getString("username", null)
                                main.post { result.success(name) }
                            } else {
                                val name = call.arguments as? String ?: error("A username is required.")
                                require(name.isNotBlank() && name.codePointCount(0, name.length) <= 24) { "Choose a username of 1–24 characters." }
                                // Confirm the disk write before telling Flutter that the name is saved.
                                check(preferences.edit().putString("username", name).commit()) { "Could not save your username. Please try again." }
                                main.post { result.success(null) }
                            }
                        } catch (error: Exception) {
                            main.post { result.error("profile", error.message ?: "Could not access your profile.", null) }
                        }
                    }
                }
            }
        val outputChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "beatrazeem/output")
        output = SynchronizedAudioPlayer { message -> main.post { outputChannel.invokeMethod("error", message) } }
        outputChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "initialize" -> { output!!.initialize(); result.success(null) }
                    "clock" -> result.success(System.nanoTime())
                    "enqueue" -> {
                        output!!.enqueue(call.argument<ByteArray>("pcm")!!,
                            call.argument<Number>("playAtNanos")!!.toLong(),
                            call.argument<Number>("sequence")!!.toLong(),
                            call.argument<Number>("capturedAtNanos")?.toLong(),
                            call.argument<Number>("roomPlayAtNanos")?.toLong() ?: call.argument<Number>("playAtNanos")!!.toLong())
                        result.success(null)
                    }
                    "volume" -> { output!!.setVolume((call.arguments as Number).toFloat()); result.success(null) }
                    "stop" -> { output!!.stop(); result.success(null) }
                    "status" -> result.success(output!!.status())
                    "dispose" -> { output!!.close(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) { result.error("output", error.message, null) }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "beatrazeem/capture_pcm")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    CaptureService.emit = { value -> main.post { events.success(value) } }
                }
                override fun onCancel(arguments: Any?) { CaptureService.emit = null }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "beatrazeem/capture")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "phoneMicrophone" -> {
                        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
                        val microphone = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
                            .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
                        result.success(microphone?.let {
                            mapOf("id" to it.id.toString(), "label" to "Phone microphone")
                        })
                    }
                    "info" -> result.success(mapOf(
                        "androidVersion" to Build.VERSION.RELEASE,
                        "sdk" to Build.VERSION.SDK_INT,
                        "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
                        "supported" to (Build.VERSION.SDK_INT >= 29)
                    ))
                    "karaokeLevels" -> {
                        CaptureService.setKaraokeLevels(
                            call.argument<Number>("singer")?.toDouble() ?: 1.0,
                            call.argument<Number>("microphone")?.toDouble() ?: 1.0,
                            call.argument<Number>("music")?.toDouble() ?: .7)
                        result.success(null)
                    }
                    "start" -> {
                        if (Build.VERSION.SDK_INT < 29) {
                            result.error("unsupported", "Device-audio sharing needs Android 10 or newer.", null)
                        } else if (pending != null) {
                            result.error("busy", "Audio permission is already being requested.", null)
                        } else {
                            pendingKaraoke = call.argument<Boolean>("karaoke") == true
                            pending = result
                            val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                            try {
                                // The room shares sound while the creator switches apps.
                                // Request display-wide consent on Android 14+, avoiding
                                // accidentally binding the session to Beatrazeem's window.
                                // No virtual display or video surface is created.
                                val permission = if (Build.VERSION.SDK_INT >= 34) {
                                    manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
                                } else manager.createScreenCaptureIntent()
                                startActivityForResult(permission, 7301)
                            } catch (error: Exception) {
                                pending = null
                                result.error("permission", error.message, null)
                            }
                        }
                    }
                    "stop" -> {
                        stopService(Intent(this, CaptureService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Platform projection result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7301) return
        val result = pending ?: return
        pending = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.error("cancelled", "Device audio sharing was cancelled.", null)
            return
        }
        CaptureService.ready = { error ->
            main.post {
                if (error == null) result.success(null)
                else result.error("capture", error, null)
            }
        }
        try {
            val intent = Intent(this, CaptureService::class.java)
                .putExtra("resultCode", resultCode).putExtra("projection", data)
                .putExtra("karaoke", pendingKaraoke)
            startForegroundService(intent)
        } catch (error: Exception) {
            CaptureService.ready = null
            result.error("capture", error.message, null)
        }
    }

    override fun onDestroy() {
        if (::localNetwork.isInitialized) localNetwork.release()
        profileIo.shutdown()
        if (isFinishing) stopService(Intent(this, CaptureService::class.java))
        output?.close(); output = null
        super.onDestroy()
    }
}
