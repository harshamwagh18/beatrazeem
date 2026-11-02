import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';
import '../core/protocol.dart';
import 'audio_timing.dart';

class AudioEngine {
  final AudioRecorder _recorder = AudioRecorder();
  static const _capture = MethodChannel('beatrazeem/capture');
  static const _output = MethodChannel('beatrazeem/output');
  RoomClock? _nativeClock;
  RoomClock? _inputClock;
  int? _nextInputCaptureUs;
  int _nativeOffsetNanos = 0;
  Future<void>? _calibration;
  void Function(Uint8List, int)? onCapturedPcm;
  static const _events = EventChannel('beatrazeem/capture_pcm');
  StreamSubscription? _input;
  final PcmFramer _framer = PcmFramer();
  final Set<AudioSource> _playing = {};
  final Set<Timer> _timers = {};
  bool _initialized = false;
  int _generation = 0;
  double volume = .75;
  double singerLevel = 1, microphoneLevel = 1, musicLevel = .7;
  int _correctionMs = 0;
  int get correctionMs => _correctionMs;
  set correctionMs(int value) => _correctionMs = value.clamp(0, 500);
  int lateFrames = 0;
  void Function(Uint8List)? onPcm;
  void Function(String)? onError;

  Future<Map<String, dynamic>?> deviceAudioInfo() async {
    if (!Platform.isAndroid) return null;
    return await _capture.invokeMapMethod<String, dynamic>('info');
  }

  Future<void> initialize() async {
    if (_initialized) return;
    if (Platform.isAndroid) {
      _output.setMethodCallHandler((call) async {
        if (call.method == 'error') onError?.call(call.arguments.toString());
      });
      await _output.invokeMethod<void>('initialize');
      await _output.invokeMethod<void>('volume', volume);
    } else {
      await SoLoud.instance.init(sampleRate: sampleRate, bufferSize: 512);
    }
    _initialized = true;
  }

  Future<void> synchronizeClock(RoomClock clock) async {
    _inputClock = clock;
    if (!Platform.isAndroid || identical(_nativeClock, clock)) return;
    if (_calibration != null) {
      await _calibration;
      return;
    }
    final work = () async {
      var bestRtt = 1 << 62;
      for (var i = 0; i < 7; i++) {
        final before = clock.now;
        final native = await _output.invokeMethod<int>('clock');
        final after = clock.now;
        if (native != null && after - before < bestRtt) {
          bestRtt = after - before;
          _nativeOffsetNanos = native - ((before + after) ~/ 2) * 1000;
        }
      }
      if (bestRtt == 1 << 62) {
        throw StateError('Could not synchronize Android audio clock.');
      }
      _nativeClock = clock;
    }();
    _calibration = work;
    try {
      await work;
    } finally {
      _calibration = null;
    }
  }

  int captureTimeUs(int nativeNanos) =>
      (nativeNanos - _nativeOffsetNanos) ~/ 1000;

  Future<void> startMic() async {
    await stopInput();
    if (!await _recorder.hasPermission()) {
      throw Exception('Allow microphone access in your device settings.');
    }
    InputDevice? phoneMicrophone;
    if (Platform.isAndroid) {
      final device = await _capture.invokeMapMethod<String, dynamic>(
        'phoneMicrophone',
      );
      if (device != null) {
        phoneMicrophone = InputDevice(
          id: device['id'] as String,
          label: device['label'] as String,
        );
      }
    }
    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        device: phoneMicrophone,
        echoCancel: true,
        noiseSuppress: true,
        // Keep Android's selected media output (including Bluetooth A2DP).
        // SCO would switch to a headset microphone/call-audio route.
        androidConfig: const AndroidRecordConfig(
          manageBluetooth: false,
          audioSource: AndroidAudioSource.mic,
          speakerphone: false,
          audioManagerMode: AudioManagerMode.modeNormal,
          muteAudio: false,
        ),
      ),
    );
    _input = stream.listen(
      _accept,
      onError: (Object error) => onError?.call('Microphone stopped: $error'),
    );
  }

  Future<void> startDeviceAudio() => _startCapturedAudio(karaoke: false);
  Future<void> startKaraoke() => _startCapturedAudio(karaoke: true);

  Future<void> setKaraokeLevels({
    double? singer,
    double? microphone,
    double? music,
  }) async {
    singerLevel = (singer ?? singerLevel).clamp(0, 1.5);
    microphoneLevel = (microphone ?? microphoneLevel).clamp(0, 2);
    musicLevel = (music ?? musicLevel).clamp(0, 1);
    if (Platform.isAndroid) {
      await _capture.invokeMethod<void>('karaokeLevels', {
        'singer': singerLevel,
        'microphone': microphoneLevel,
        'music': musicLevel,
      });
    }
  }

  Future<void> _startCapturedAudio({required bool karaoke}) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Other-app audio sharing is currently available on Android 10 or newer.',
      );
    }
    await stopInput();
    if (!await _recorder.hasPermission()) {
      throw Exception('Audio permission is needed to share device sound.');
    }
    _input = _events.receiveBroadcastStream().listen((event) {
      if (event is Map &&
          event['pcm'] is Uint8List &&
          event['capturedAtNanos'] is int) {
        final bytes = event['pcm'] as Uint8List;
        if (bytes.length == frameBytes && onCapturedPcm != null) {
          onCapturedPcm!(bytes, captureTimeUs(event['capturedAtNanos'] as int));
        } else {
          _accept(bytes);
        }
      }
      if (event is Uint8List) _accept(event);
      if (event is String) onError?.call(event);
    }, onError: (Object e) => onError?.call('Device audio stopped: $e'));
    try {
      if (karaoke) await setKaraokeLevels();
      await _capture.invokeMethod<void>('start', {'karaoke': karaoke});
    } catch (_) {
      await _input?.cancel();
      _input = null;
      rethrow;
    }
  }

  void _accept(Uint8List data) {
    final frames = _framer.add(data).toList();
    if (frames.isEmpty) return;
    final clock = _inputClock;
    if (clock != null) {
      _nextInputCaptureUs ??= clock.now - frames.length * frameUs;
    }
    for (final frame in frames) {
      if (_nextInputCaptureUs != null && onCapturedPcm != null) {
        onCapturedPcm!(frame, _nextInputCaptureUs!);
        _nextInputCaptureUs = _nextInputCaptureUs! + frameUs;
      } else {
        onPcm?.call(frame);
      }
    }
  }

  Future<void> stopInput() async {
    await _input?.cancel();
    _input = null;
    await _recorder.stop();
    if (Platform.isAndroid) await _capture.invokeMethod<void>('stop');
    _framer.clear();
    _nextInputCaptureUs = null;
  }

  Future<void> play(
    AudioFrame frame,
    RoomClock clock, {
    required bool host,
  }) async {
    if (!_initialized) return;
    if (Platform.isAndroid) {
      final generation = _generation;
      try {
        await synchronizeClock(clock);
        if (generation != _generation) return;
        final clockOffset = host ? 0 : clock.offset;
        final roomDeadline = frame.playAt - clockOffset;
        final deadline = roomDeadline + correctionMs * 1000;
        if (deadline + frame.durationUs <= clock.now) {
          lateFrames++;
          return;
        }
        await _output.invokeMethod<void>('enqueue', {
          'pcm': frame.pcm,
          'sequence': frame.sequence,
          'playAtNanos': deadline * 1000 + _nativeOffsetNanos,
          'roomPlayAtNanos': roomDeadline * 1000 + _nativeOffsetNanos,
          if (frame.capturedAt != null)
            'capturedAtNanos':
                (frame.capturedAt! - clockOffset) * 1000 + _nativeOffsetNanos,
        });
      } catch (error) {
        onError?.call('Audio output failed: $error');
      }
      return;
    }
    final generation = _generation;
    final deadline =
        frame.playAt - (host ? 0 : clock.offset) + correctionMs * 1000;
    if (deadline < clock.now - 20000) {
      lateFrames++;
      return;
    }
    if (deadline - clock.now > 2000000 || _playing.length > 24) return;
    AudioSource? sound;
    try {
      sound = SoLoud.instance.setBufferStream(
        maxBufferSizeBytes: frameBytes * 2,
        bufferingType: BufferingType.released,
        bufferingTimeNeeds: 0,
        sampleRate: sampleRate,
        channels: Channels.mono,
        format: BufferType.s16le,
      );
      _playing.add(sound);
      SoLoud.instance.addAudioDataStream(sound, frame.pcm);
      SoLoud.instance.setDataIsEnded(sound);
      final handle = SoLoud.instance.play(sound, volume: volume, paused: true);
      if (generation != _generation) {
        if (_playing.remove(sound)) await SoLoud.instance.disposeSource(sound);
        return;
      }
      final remaining = deadline - clock.now;
      if (remaining < -20000) {
        lateFrames++;
        _playing.remove(sound);
        await SoLoud.instance.disposeSource(sound);
        return;
      }
      SoLoud.instance.setDelaySamples(
        handle,
        (remaining.clamp(0, 2000000) * sampleRate ~/ 1000000),
      );
      SoLoud.instance.setPause(handle, false);
      final ownedSound = sound;
      late final Timer timer;
      timer = Timer(
        Duration(microseconds: remaining.clamp(0, 2000000) + frameUs + 100000),
        () async {
          _timers.remove(timer);
          if (_playing.remove(ownedSound)) {
            await SoLoud.instance.disposeSource(ownedSound);
          }
        },
      );
      _timers.add(timer);
    } catch (error) {
      if (sound != null && _playing.remove(sound)) {
        await SoLoud.instance.disposeSource(sound);
      }
      onError?.call('Audio output failed: $error');
    }
  }

  Future<AudioTiming> readTiming() async {
    if (!_initialized || !Platform.isAndroid) return const AudioTiming();
    final values = await _output.invokeMapMethod<String, dynamic>('status');
    return values == null ? const AudioTiming() : AudioTiming.fromMap(values);
  }

  void setVolume(double value) {
    volume = value.clamp(0, 1);
    if (_initialized && Platform.isAndroid) {
      unawaited(
        _output.invokeMethod<void>('volume', volume).catchError((Object error) {
          onError?.call('Volume update failed: $error');
        }),
      );
    }
  }

  Future<void> stopOutput() async {
    _generation++;
    if (_initialized && Platform.isAndroid) {
      await _output.invokeMethod<void>('stop');
      lateFrames = 0;
      return;
    }
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    final sounds = _playing.toList();
    _playing.clear();
    for (final sound in sounds) {
      await SoLoud.instance.disposeSource(sound);
    }
    lateFrames = 0;
  }

  Future<void> dispose() async {
    await stopInput();
    await stopOutput();
    await _recorder.dispose();
    if (_initialized) {
      if (Platform.isAndroid) {
        await _output.invokeMethod<void>('dispose');
        _output.setMethodCallHandler(null);
      } else {
        SoLoud.instance.deinit();
      }
    }
  }
}
