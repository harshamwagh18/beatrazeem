import 'protocol.dart';

/// Keeps app-audio deadlines tied to capture time, even after callback stalls.
///
/// `capturedAtUs` must be the first PCM sample's capture time mapped into the
/// same monotonic clock as `nowUs`. Never replace it with callback arrival time:
/// doing so turns queued old audio into an ever-growing playback delay.
class CaptureTimeline {
  CaptureTimeline({this.playoutDelayUs = 200000}) {
    if (playoutDelayUs <= 0) {
      throw ArgumentError.value(playoutDelayUs, 'playoutDelayUs');
    }
  }

  final int playoutDelayUs;
  int? _lastCaptureUs;
  int lateFrames = 0;
  int invalidFrames = 0;

  /// Returns the unchanged capture-based deadline, or null for unusable audio.
  ///
  /// Partially late blocks keep their original deadline so the native output
  /// can trim their expired prefix. Completely expired blocks are discarded.
  int? schedule({
    required int capturedAtUs,
    required int nowUs,
    int durationUs = frameUs,
  }) {
    if (durationUs <= 0 ||
        durationUs > 1000000 ||
        capturedAtUs > nowUs + 20000 ||
        (_lastCaptureUs != null && capturedAtUs <= _lastCaptureUs!)) {
      invalidFrames++;
      return null;
    }
    _lastCaptureUs = capturedAtUs;
    final deadline = capturedAtUs + playoutDelayUs;
    if (deadline + durationUs <= nowUs) {
      lateFrames++;
      return null;
    }
    return deadline;
  }

  void reset() {
    _lastCaptureUs = null;
    lateFrames = 0;
    invalidFrames = 0;
  }
}
