import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/core/clock_link.dart';
import 'package:beatrazeem/core/protocol.dart';

void main() {
  test(
    'direct clock synchronizes without an audio/TCP connection and rejects wrong codes',
    () async {
      final reservation = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      reservation.close();
      final host = ClockLink(RoomClock()), clock = RoomClock();
      final guest = ClockLink(clock);
      addTearDown(() {
        guest.close();
        host.close();
      });
      await host.serve(port, '123456');
      await guest.connect('127.0.0.1', port, '654321');
      guest.ping();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(guest.healthy, isFalse);
      expect(clock.ready, isFalse);
      await guest.connect('127.0.0.1', port, '123456');
      for (var i = 0; i < 8; i++) {
        guest.ping();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(clock.ready, isTrue);
      expect(guest.healthy, isTrue);
      guest.close();
      expect(guest.healthy, isFalse);
    },
  );
}
