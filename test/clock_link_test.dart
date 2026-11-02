import 'dart:io';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/core/clock_link.dart';
import 'package:beatrazeem/core/protocol.dart';

void main() {
  test(
    'authenticated clock rejects replay storms and recovers after its work budget',
    () async {
      final reservation = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      reservation.close();
      final host = ClockLink(RoomClock());
      final raw = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() {
        raw.close();
        host.close();
      });
      final key = SecretKey(List<int>.filled(32, 7));
      await host.serve(port, '123456', requireAuthentication: true);
      host.authorize('session', key);
      final replies = <dynamic>[];
      raw.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? d;
        while ((d = raw.receive()) != null) {
          replies.add(jsonDecode(utf8.decode(d!.data)));
        }
      });
      Future<List<int>> request(int sent) async {
        final payload = utf8.encode(
          jsonEncode({'type': 'clockPing', 'code': '123456', 'sent': sent}),
        );
        final mac = await Hmac.sha256().calculateMac(payload, secretKey: key);
        return utf8.encode(
          jsonEncode({
            'session': 'session',
            'payload': base64Encode(payload),
            'mac': base64Encode(mac.bytes),
          }),
        );
      }

      final packet = await request(1);
      for (var i = 0; i < 400; i++) {
        raw.send(packet, InternetAddress.loopbackIPv4, port);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(replies.length, 1);
      await Future<void>.delayed(const Duration(milliseconds: 1050));
      raw.send(await request(2), InternetAddress.loopbackIPv4, port);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(replies.length, 2);
    },
  );
  test(
    'secured clock accepts only an approved session key and revokes it on leave',
    () async {
      final reservation = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      reservation.close();
      final host = ClockLink(RoomClock());
      final clock = RoomClock(), guest = ClockLink(RoomClock());
      final valid = ClockLink(clock);
      addTearDown(() {
        host.close();
        guest.close();
        valid.close();
      });
      final key = SecretKey(List<int>.filled(32, 19));
      await host.serve(port, '123456', requireAuthentication: true);
      host.authorize('approved-session', key);
      await guest.connect(
        '127.0.0.1',
        port,
        '123456',
        sessionId: 'approved-session',
        authenticationKey: SecretKey(List<int>.filled(32, 20)),
      );
      guest.ping();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(guest.healthy, isFalse);
      await valid.connect(
        '127.0.0.1',
        port,
        '123456',
        sessionId: 'approved-session',
        authenticationKey: key,
      );
      for (var i = 0; i < 8; i++) {
        valid.ping();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(valid.healthy, isTrue);
      expect(clock.ready, isTrue);
      host.revoke('approved-session');
      valid.resetMeasurements();
      valid.ping();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(valid.healthy, isFalse);
      await guest.connect('127.0.0.1', port, '123456');
      guest.ping();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(guest.healthy, isFalse);
    },
  );
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
