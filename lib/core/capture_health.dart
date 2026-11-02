import 'dart:typed_data';

/// Distinguishes a live PCM signal from zero-filled capture and a stalled input.
/// Silence alone cannot identify an app's capture policy.
class CaptureHealth {
  int? _started;
  int? _lastFrame;
  int? _lastSignal;
  int frames = 0;
  double peak = 0;

  void start(int now) {
    _started = now;
    _lastFrame = null;
    _lastSignal = null;
    frames = 0;
    peak = 0;
  }

  void observe(Uint8List pcm, int now) {
    if (_started == null) return;
    final data = ByteData.sublistView(pcm);
    var maximum = 0;
    for (var i = 0; i + 1 < pcm.length; i += 2) {
      final value = data.getInt16(i, Endian.little).abs();
      if (value > maximum) maximum = value;
    }
    frames++;
    _lastFrame = now;
    peak = maximum / 32768;
    if (maximum > 4) _lastSignal = now;
  }

  String status(int now) {
    final started = _started;
    if (started == null) return 'idle';
    if (_lastFrame == null) {
      return now - started < 5000000 ? 'waiting' : 'noData';
    }
    if (now - _lastFrame! >= 3000000) return 'noData';
    if (_lastSignal != null && now - _lastSignal! < 5000000) return 'live';
    return now - started < 5000000 ? 'waiting' : 'silent';
  }

  void stop() {
    _started = null;
    _lastFrame = null;
    _lastSignal = null;
    peak = 0;
    frames = 0;
  }
}
