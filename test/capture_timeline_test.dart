import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/core/capture_timeline.dart';

void main() {
  test('callback jitter does not move captured audio to a later timeline', () {
    final timeline = CaptureTimeline();
    final deadlines = [
      timeline.schedule(capturedAtUs: 1000000, nowUs: 1100000),
      timeline.schedule(capturedAtUs: 1100000, nowUs: 1250000),
      timeline.schedule(capturedAtUs: 1200000, nowUs: 1370000),
    ];
    expect(deadlines, [1200000, 1300000, 1400000]);
  });

  test('a callback backlog is dropped instead of replayed in the future', () {
    final timeline = CaptureTimeline();
    expect(timeline.schedule(capturedAtUs: 1000000, nowUs: 2000000), isNull);
    expect(timeline.schedule(capturedAtUs: 1100000, nowUs: 2000000), isNull);
    expect(timeline.schedule(capturedAtUs: 1800000, nowUs: 2000000), 2000000);
    expect(timeline.lateFrames, 2);
  });

  test('partly late blocks retain deadlines for native prefix trimming', () {
    final timeline = CaptureTimeline();
    expect(timeline.schedule(capturedAtUs: 1000000, nowUs: 1210000), 1200000);
    expect(timeline.schedule(capturedAtUs: 1100000, nowUs: 1600000), isNull);
  });

  test(
    'out-of-order, duplicate and implausible future captures are rejected',
    () {
      final timeline = CaptureTimeline();
      expect(timeline.schedule(capturedAtUs: 1000000, nowUs: 1100000), 1200000);
      expect(timeline.schedule(capturedAtUs: 1000000, nowUs: 1200000), isNull);
      expect(timeline.schedule(capturedAtUs: 900000, nowUs: 1200000), isNull);
      expect(timeline.schedule(capturedAtUs: 2000000, nowUs: 1200000), isNull);
      expect(timeline.schedule(capturedAtUs: 1100000, nowUs: 1200000), 1300000);
      expect(timeline.invalidFrames, 3);
    },
  );

  test('new sharing sessions reset capture order and diagnostics', () {
    final timeline = CaptureTimeline();
    timeline.schedule(capturedAtUs: 1000000, nowUs: 2000000);
    timeline.schedule(capturedAtUs: 500000, nowUs: 2000000);
    timeline.reset();
    expect(timeline.lateFrames, 0);
    expect(timeline.invalidFrames, 0);
    expect(timeline.schedule(capturedAtUs: 100000, nowUs: 200000), 300000);
  });
}
