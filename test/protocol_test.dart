import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/core/protocol.dart';

void main() {
  test(
    '20ms frames carry capture time for delay measurement and reject impossible timing',
    () {
      final pcm = Uint8List(frameBytes)..[0] = 42;
      final encoded = AudioFrame(5, 1200000, pcm, capturedAt: 1000000).encode();
      final decoded = AudioFrame.decode(encoded)!;
      expect(decoded.capturedAt, 1000000);
      expect(decoded.playAt - decoded.capturedAt!, 200000);
      expect(decoded.durationUs, 20000);
      expect(decoded.pcm, pcm);
      expect(AudioFrame.decode(encoded.sublist(0, 24)), isNull);
      final invalid = AudioFrame(5, 900000, pcm, capturedAt: 1000000).encode();
      expect(AudioFrame.decode(invalid), isNull);
      final legacy = AudioFrame.decode(
        AudioFrame(1, 1400000, Uint8List(9600)).encode(),
      )!;
      expect(legacy.durationUs, 100000);
      expect(legacy.capturedAt, isNull);
    },
  );

  test('room codes have exactly six digits and retain leading zero input', () {
    for (var i = 0; i < 1000; i++) {
      expect(validRoomCode(createRoomCode()), isTrue);
    }
    expect(validRoomCode('012345'), isTrue);
    expect(validRoomCode('12345'), isFalse);
    expect(validRoomCode('1234567'), isFalse);
    expect(validRoomCode('abc123'), isFalse);
  });
  test('binary frames preserve PCM and timing and reject bad lengths', () {
    final pcm = Uint8List.fromList(List.generate(frameBytes, (i) => i % 256));
    final bytes = AudioFrame(47, 1234567890, pcm).encode();
    final frame = AudioFrame.decode(bytes)!;
    expect(frame.sequence, 47);
    expect(frame.playAt, 1234567890);
    expect(frame.pcm, pcm);
    expect(AudioFrame.decode(bytes.sublist(0, bytes.length - 1)), isNull);
    bytes[0] = 0;
    expect(AudioFrame.decode(bytes), isNull);
  });
  test('reframing preserves partial samples across arbitrary callbacks', () {
    final framer = PcmFramer();
    final input = Uint8List.fromList(
      List.generate(frameBytes * 2, (i) => i % 255),
    );
    expect(framer.add(Uint8List.sublistView(input, 0, 31)).toList(), isEmpty);
    final frames = framer.add(Uint8List.sublistView(input, 31)).toList();
    expect(frames.length, 2);
    expect(frames.expand((x) => x).toList(), input);
  });
  test('clock locks after three exchanges and resets between rooms', () {
    final clock = RoomClock();
    clock.sample(1000, 1600, 1200); // offset 500, RTT 200
    clock.sample(2000, 2800, 2600); // offset 500, RTT 600
    clock.sample(3000, 3550, 3100); // offset 500, RTT 100
    expect(clock.ready, isTrue);
    expect(clock.offset, 500);
    expect(clock.rtt, 100);
    clock.reset();
    expect(clock.ready, isFalse);
    expect(clock.offset, 0);
  });

  test('clock removes creator processing time from offset and network RTT', () {
    final clock = RoomClock();
    for (var i = 0; i < 3; i++) {
      final sent = 100000 + i * 100000;
      // Creator is 50ms ahead, each network leg takes 2ms, and the
      // creator spends 40ms processing the request before replying.
      clock.sample(sent, sent + 52000, sent + 44000, hostSent: sent + 92000);
    }
    expect(clock.ready, isTrue);
    expect(clock.offset, 50000);
    expect(clock.rtt, 4000);
  });

  test('clock rejects delayed samples and slews renewed estimates', () {
    final clock = RoomClock();
    for (var i = 0; i < 3; i++) {
      final sent = 100000 + i * 100000;
      clock.sample(sent, sent + 11000, sent + 2000);
    }
    // A congested return path must not shift an established clock.
    clock.sample(500000, 511000, 600000);
    expect(clock.offset, 10000);
    // Once old measurements age out, even a very different measurement
    // cannot abruptly move the audio timeline by its entire 40ms error.
    clock.sample(5000000, 5051000, 5002000);
    expect(clock.ready, isTrue);
    expect(clock.offset, 11000);
    clock.sample(5500000, 5551000, 5502000);
    expect(clock.offset, 12000);
  });

  test('clock follows gradual drift without retaining a stale best packet', () {
    final clock = RoomClock();
    var previous = 0;
    for (var i = 0; i < 64; i++) {
      final sent = 100000 + i * 500000;
      final actualOffset = 100000 + i * 100; // 200ppm independent clock drift.
      final roundTrip = 2000 + (i % 8) * 100;
      clock.sample(
        sent,
        sent + actualOffset + roundTrip ~/ 2,
        sent + roundTrip,
      );
      if (i > 2) {
        expect((clock.offset - previous).abs(), lessThanOrEqualTo(1000));
      }
      previous = clock.offset;
    }
    expect(clock.offset, closeTo(106300, 1000));
  });

  test('invalid and out-of-order exchanges cannot change the clock', () {
    final clock = RoomClock();
    for (var i = 0; i < 3; i++) {
      final sent = 100000 + i * 100000;
      clock.sample(sent, sent + 6000, sent + 2000);
    }
    final initialOffset = clock.offset;
    clock.sample(500000, 505000, 499999); // Negative elapsed time.
    clock.sample(
      500000,
      505000,
      502000,
      hostSent: 504000,
    ); // Host time reversed.
    clock.sample(500000, 505000, 502000, hostSent: 508000); // Impossible RTT.
    clock.sample(500000, 505000, 800000); // Excessively delayed exchange.
    clock.sample(100000, 190000, 102000); // Replayed/out-of-order exchange.
    expect(clock.offset, initialOffset);
    expect(clock.rtt, 2000);
    clock.reset();
    clock.sample(
      1,
      100,
      300002,
    ); // One invalid sample does not establish readiness.
    expect(clock.ready, isFalse);
    expect(clock.offset, 0);
  });
}
