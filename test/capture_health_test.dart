import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/core/capture_health.dart';
import 'package:beatrazeem/core/protocol.dart';

void main() {
  test('consent startup gets time before missing input is reported', () {
    final health = CaptureHealth();
    expect(health.status(0), 'idle');
    health.start(1000000);
    expect(health.status(5999999), 'waiting');
    expect(health.status(6000000), 'noData');
  });

  test('zero-filled input is silent, not a stalled recorder', () {
    final health = CaptureHealth()..start(0);
    final silence = Uint8List(frameBytes);
    for (var now = 100000; now <= 5000000; now += 100000) {
      health.observe(silence, now);
    }
    expect(health.status(5000000), 'silent');
    expect(health.frames, 50);
    expect(health.peak, 0);
    expect(health.status(8000000), 'noData');
  });

  test('signal detection checks all samples and recovers after silence', () {
    final health = CaptureHealth()..start(0);
    final signal = Uint8List(frameBytes);
    // This sample falls between the UI meter's former 16-sample stride.
    ByteData.sublistView(signal).setInt16(2, -32768, Endian.little);
    health.observe(signal, 100000);
    expect(health.status(100000), 'live');
    expect(health.peak, 1);
    health.observe(Uint8List(frameBytes), 5000000);
    expect(health.status(5000000), 'live');
    expect(health.status(5100000), 'silent');
    health.observe(signal, 6000000);
    expect(health.status(6000000), 'live');
    expect(health.status(9000000), 'noData');
    health.observe(signal, 9100000);
    expect(health.status(9100000), 'live');
  });

  test('stopping and restarting discard prior signal state', () {
    final health = CaptureHealth()..start(0);
    final signal = Uint8List(frameBytes)..[0] = 50;
    health.observe(signal, 100000);
    health.stop();
    health.observe(signal, 200000);
    expect(health.status(200000), 'idle');
    expect(health.frames, 0);
    expect(health.peak, 0);
    health.start(300000);
    expect(health.status(300000), 'waiting');
  });
}
