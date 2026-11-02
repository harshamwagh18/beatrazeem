import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/core/secure_room_socket.dart';
import 'package:beatrazeem/core/transport.dart';

void main() {
  test(
    'both phones must approve before the identity or room data is exchanged',
    () async {
      final host = RoomTransport(), guest = RoomTransport();
      final hostApproval = Completer<bool>(), guestApproval = Completer<bool>();
      final hostShown = Completer<String>(), guestShown = Completer<String>();
      host.onVerifyPeer = (v) {
        hostShown.complete(v.verificationCode);
        return hostApproval.future;
      };
      guest.onVerifyPeer = (v) {
        guestShown.complete(v.verificationCode);
        return guestApproval.future;
      };
      addTearDown(() async {
        await guest.close();
        await host.close();
      });
      await host.create(
        '123456',
        username: 'Private host',
        name: 'Private room',
      );
      final joining = guest.join(
        '127.0.0.1',
        host.port,
        '123456',
        username: 'Private guest',
      );
      final codes = await Future.wait([
        hostShown.future,
        guestShown.future,
      ]).timeout(const Duration(seconds: 3));
      expect(codes.first, codes.last);
      expect(codes.first, matches(RegExp(r'^\d{6}$')));
      expect(host.members, hasLength(1));
      expect(guest.members, isEmpty);
      expect(guest.roomName, isNull);
      guestApproval.complete(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(host.members, hasLength(1));
      expect(guest.roomName, isNull);
      hostApproval.complete(true);
      await joining;
      expect(host.members.last.name, 'Private guest');
      expect(guest.roomName, 'Private room');
      expect(guest.hasDirectClock, isTrue);
    },
  );

  test(
    'declining verification leaves no membership or personal data on the host',
    () async {
      final host = RoomTransport()..onVerifyPeer = (_) async => false;
      final guest = RoomTransport()..onVerifyPeer = (_) async => true;
      addTearDown(() async {
        await guest.close();
        await host.close();
      });
      await host.create('123456', username: 'Host', name: 'Room');
      await expectLater(
        guest.join('127.0.0.1', host.port, '123456', username: 'Private guest'),
        throwsA(anything),
      );
      expect(host.count, 1);
      expect(guest.connected, isFalse);
      expect(guest.members, isEmpty);
    },
  );

  test(
    'an unset verification callback never silently approves a device',
    () async {
      final host = RoomTransport();
      final guest = RoomTransport()..onVerifyPeer = (_) async => true;
      addTearDown(() async {
        await guest.close();
        await host.close();
      });
      await host.create('123456', username: 'Host', name: 'Room');
      await expectLater(
        guest.join('127.0.0.1', host.port, '123456', username: 'Private guest'),
        throwsA(anything),
      );
      expect(host.count, 1);
    },
  );

  test(
    'wire messages encrypt identity and audio; both directions retain order',
    () async {
      final pair = await _WirePair.connect();
      addTearDown(pair.close);
      final received = <dynamic>[];
      final arrived = Completer<void>();
      pair.host.listen((m) {
        received.add(m);
        if (received.length == 3) arrived.complete();
      });
      final back = pair.client.stream.first;
      pair.client.add('private metadata');
      pair.client.add(Uint8List.fromList([12, 34, 56, 78]));
      pair.client.add('end');
      pair.host.add('reverse direction');
      await arrived.future.timeout(const Duration(seconds: 3));
      expect(received[0], 'private metadata');
      expect(received[1], [12, 34, 56, 78]);
      expect(received[2], 'end');
      expect(await back, 'reverse direction');
      expect(pair.host.peerIdentity, 'private username');
      expect(pair.host.verificationCode, pair.client.verificationCode);
      final wireText = pair.wire
          .map(
            (v) => v is String
                ? v
                : utf8.decode(v as List<int>, allowMalformed: true),
          )
          .join();
      expect(wireText, isNot(contains('private username')));
      expect(wireText, isNot(contains('private metadata')));
      expect(wireText, isNot(contains('reverse direction')));
    },
  );

  for (final mutation in ['tamper', 'replay', 'plaintext']) {
    test(
      '$mutation is rejected before unauthenticated audio reaches the app',
      () async {
        final pair = await _WirePair.connect();
        addTearDown(pair.close);
        final received = <dynamic>[];
        final ended = Completer<void>();
        pair.host.listen(received.add, onDone: ended.complete);
        pair.mutation = mutation;
        pair.client.add('audio test');
        await ended.future.timeout(const Duration(seconds: 3));
        expect(received, mutation == 'replay' ? ['audio test'] : isEmpty);
      },
    );
  }
}

class _WirePair {
  late SecureRoomSocket host, client;
  late HttpServer server, proxy;
  final sockets = <WebSocket>[];
  final wire = <dynamic>[];
  String? mutation;
  static Future<_WirePair> connect() async {
    final pair = _WirePair();
    final accepted = Completer<SecureRoomSocket>();
    pair.server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    pair.server.listen((request) async {
      final raw = await WebSocketTransformer.upgrade(request);
      pair.sockets.add(raw);
      try {
        accepted.complete(
          await SecureRoomSocket.establish(
            raw,
            roomCode: '123456',
            isHost: true,
            verify: (_) async => true,
          ),
        );
      } catch (error, stack) {
        accepted.completeError(error, stack);
      }
    });
    pair.proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    pair.proxy.listen((request) async {
      final downstream = await WebSocketTransformer.upgrade(request);
      final upstream = await WebSocket.connect(
        'ws://127.0.0.1:${pair.server.port}/',
      );
      pair.sockets.addAll([downstream, upstream]);
      downstream.listen((m) {
        pair.wire.add(m);
        final mutation = pair.mutation;
        pair.mutation = null;
        if (mutation == 'tamper' && m is List<int>) {
          final changed = Uint8List.fromList(m);
          changed[changed.length - 1] ^= 1;
          upstream.add(changed);
        } else if (mutation == 'plaintext') {
          upstream.add('private spoofed audio');
        } else {
          upstream.add(m);
          if (mutation == 'replay') upstream.add(m);
        }
      }, onDone: () => upstream.close());
      upstream.listen((m) {
        pair.wire.add(m);
        downstream.add(m);
      }, onDone: () => downstream.close());
    });
    final raw = await WebSocket.connect('ws://127.0.0.1:${pair.proxy.port}/');
    pair.sockets.add(raw);
    pair.client = await SecureRoomSocket.establish(
      raw,
      roomCode: '123456',
      isHost: false,
      verify: (_) async => true,
      username: 'private username',
    );
    pair.host = await accepted.future.timeout(const Duration(seconds: 3));
    return pair;
  }

  Future<void> close() async {
    await client.close();
    await host.close();
    for (final socket in sockets) {
      await socket.close();
    }
    await proxy.close(force: true);
    await server.close(force: true);
  }
}
