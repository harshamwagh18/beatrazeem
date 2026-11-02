import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/core/protocol.dart';
import 'package:beatrazeem/core/transport.dart';
import 'package:beatrazeem/core/room_member.dart';
import 'package:beatrazeem/core/secure_room_socket.dart';

RoomTransport _room() => RoomTransport()..onVerifyPeer = (_) async => true;

void main() {
  test(
    'a listener can recheck timing without disconnecting or losing its name',
    () async {
      final host = _room(), listener = _room();
      addTearDown(() async {
        await listener.close();
        await host.close();
      });
      await host.create('123456', username: 'Creator', name: 'Music');
      await listener.join('127.0.0.1', host.port, '123456', username: 'Aisha');
      final id = listener.localMemberId;
      listener.clock.offset += 50000;
      await listener.resynchronize();
      expect(listener.clock.ready, isTrue);
      expect(listener.connected, isTrue);
      expect(listener.localMemberId, id);
      expect(listener.members.last.name, 'Aisha');
      final got = Completer<AudioFrame>();
      listener.onAudio = got.complete;
      final captured = host.clock.now;
      host.broadcast(
        AudioFrame(
          1,
          captured + playoutDelayUs,
          Uint8List(frameBytes),
          capturedAt: captured,
        ),
      );
      expect(
        (await got.future.timeout(const Duration(seconds: 2))).capturedAt,
        captured,
      );
    },
  );

  test(
    'old listener protocol receives an update requirement instead of silent audio',
    () async {
      final host = _room();
      addTearDown(host.close);
      await host.create('123456', username: 'Creator', name: 'Music');
      await expectLater(
        WebSocket.connect(
          'ws://127.0.0.1:${host.port}/room',
          headers: {'x-beatrazeem-code': '123456'},
        ),
        throwsA(
          isA<WebSocketException>().having(
            (e) => e.httpStatusCode,
            'status',
            HttpStatus.upgradeRequired,
          ),
        ),
      );
    },
  );

  test(
    'a nine-frame capture burst resumes on ACK without losing its last frame',
    () async {
      final host = _room();
      await host.create('123456', username: 'Creator', name: 'Timing room');
      final listener = await _AudioListener.connect(host);
      addTearDown(() async {
        await listener.close();
        await host.close();
      });
      final captured = host.clock.now - 8 * frameUs;
      for (var sequence = 0; sequence < 9; sequence++) {
        final captureTime = captured + sequence * frameUs;
        host.broadcast(
          AudioFrame(
            sequence,
            captureTime + playoutDelayUs,
            Uint8List(frameBytes),
            capturedAt: captureTime,
          ),
        );
      }
      await listener.waitForCount(8);
      expect(
        listener.frames.map((frame) => frame.sequence),
        List.generate(8, (i) => i),
      );
      listener.acknowledge(7);
      await listener.waitForCount(9);
      expect(
        listener.frames.map((frame) => frame.sequence),
        List.generate(9, (i) => i),
      );
      expect(listener.frames.last.capturedAt, captured + 8 * frameUs);
    },
  );

  test(
    'a stalled listener cannot accumulate an unbounded audio backlog',
    () async {
      final host = _room();
      await host.create('123456', username: 'Creator', name: 'Timing room');
      final slow = await _AudioListener.connect(host);
      addTearDown(() async {
        await slow.close();
        await host.close();
      });
      final pcm = Uint8List(frameBytes);
      for (var sequence = 0; sequence < 50; sequence++) {
        host.broadcast(AudioFrame(sequence, host.clock.now + 500000, pcm));
      }
      await slow.waitForCount(8);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        slow.frames.map((frame) => frame.sequence),
        List.generate(8, (i) => i),
      );
      slow.acknowledge(7);
      await slow.waitForCount(16);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        slow.frames.skip(8).map((frame) => frame.sequence),
        List.generate(8, (i) => i + 40),
      );
      slow.acknowledge(47);
      await slow.waitForCount(18);
      expect(slow.frames.skip(16).map((frame) => frame.sequence), [48, 49]);
      host.broadcast(AudioFrame(50, host.clock.now + 500000, pcm));
      await slow.waitForCount(19);
      expect(slow.frames.last.sequence, 50);
    },
  );

  test(
    'expired queued audio is discarded when an ACK releases credit',
    () async {
      final host = _room();
      await host.create('123456', username: 'Creator', name: 'Timing room');
      final listener = await _AudioListener.connect(host);
      addTearDown(() async {
        await listener.close();
        await host.close();
      });
      final deadline = host.clock.now + 100000;
      for (var sequence = 0; sequence < 9; sequence++) {
        host.broadcast(AudioFrame(sequence, deadline, Uint8List(frameBytes)));
      }
      await listener.waitForCount(8);
      await Future<void>.delayed(const Duration(milliseconds: 160));
      listener.acknowledge(7);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(listener.frames.length, 8);
      host.broadcast(
        AudioFrame(9, host.clock.now + playoutDelayUs, Uint8List(frameBytes)),
      );
      await listener.waitForCount(9);
      expect(listener.frames.map((frame) => frame.sequence), [
        ...List.generate(8, (i) => i),
        9,
      ]);
    },
  );

  for (final sourceChange in [true, false]) {
    test(
      '${sourceChange ? 'source changes' : 'sequence restarts'} clear unsent audio without reusing old ACK credit',
      () async {
        final host = _room();
        await host.create('123456', username: 'Creator', name: 'Timing room');
        final listener = await _AudioListener.connect(host);
        addTearDown(() async {
          await listener.close();
          await host.close();
        });
        final deadline = host.clock.now + 500000;
        for (var sequence = 0; sequence < 9; sequence++) {
          host.broadcast(
            AudioFrame(sequence, deadline, Uint8List(frameBytes)..[0] = 1),
          );
        }
        await listener.waitForCount(8);
        if (sourceChange) {
          host.setSource('idle');
          host.setSource('app');
        }
        for (var sequence = 0; sequence < 9; sequence++) {
          host.broadcast(
            AudioFrame(sequence, deadline, Uint8List(frameBytes)..[0] = 2),
          );
        }
        listener.acknowledge(0);
        await listener.waitForCount(9);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(listener.frames.length, 9);
        expect(listener.frames.last.pcm.first, 2);
        expect(listener.frames.last.sequence, 0);
        // ACK 7 belongs to the previous stream. It releases seven slots,
        // leaving the new stream's sequence 0 outstanding.
        listener.acknowledge(7);
        await listener.waitForCount(16);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(listener.frames.length, 16);
        listener.acknowledge(0);
        await listener.waitForCount(17);
        final current = listener.frames.skip(8);
        expect(
          current.map((frame) => frame.sequence),
          List.generate(9, (i) => i),
        );
        expect(current.every((frame) => frame.pcm.first == 2), isTrue);
      },
    );
  }

  test(
    'profile renames reach every member without rejoining or interrupting audio',
    () async {
      final host = _room(), a = _room(), b = _room();
      addTearDown(() async {
        await a.close();
        await b.close();
        await host.close();
      });
      await host.create('012345', username: 'Host', name: 'Music room');
      await a.join('127.0.0.1', host.port, '012345', username: 'Aisha');
      await b.join('127.0.0.1', host.port, '012345', username: 'Arjun');
      final ids = host.members.map((m) => m.id).toList();
      final hostChanged = b.changes.stream.firstWhere(
        (_) => b.members.first.name == 'Razeem',
      );
      host.rename('  Razeem  ');
      await hostChanged.timeout(const Duration(seconds: 2));
      final seenByA = a.changes.stream.firstWhere(
        (_) => a.members.any((m) => m.name == 'Zoë 🎵'),
      );
      final seenByB = b.changes.stream.firstWhere(
        (_) => b.members.any((m) => m.name == 'Zoë 🎵'),
      );
      a.rename('Zoë 🎵');
      await Future.wait([seenByA, seenByB]).timeout(const Duration(seconds: 2));
      expect(host.members.map((m) => m.name), ['Razeem', 'Zoë 🎵', 'Arjun']);
      expect(host.members.map((m) => m.id), ids);
      expect(host.members.where((m) => m.isHost).single.id, 'host');
      expect(() => a.rename(' '), throwsFormatException);
      expect(host.count, 3);
      expect(a.localMemberId, ids[1]);
      final sound = Completer<AudioFrame>();
      a.onAudio = sound.complete;
      host.broadcast(
        AudioFrame(1, host.clock.now + 450000, Uint8List(frameBytes)..[0] = 99),
      );
      expect(
        (await sound.future.timeout(const Duration(seconds: 2))).pcm[0],
        99,
      );
      expect(a.connected && b.connected, isTrue);
    },
  );

  test(
    'room names and Unicode members synchronize, leave and rejoin with distinct identities',
    () async {
      final host = _room(), a = _room(), b = _room();
      addTearDown(() async {
        await a.close();
        await b.close();
        await host.close();
      });
      await host.create(
        '012345',
        username: '  Razeem  ',
        name: 'Sunset 🌅 sessions',
      );
      expect(host.members.single.name, 'Razeem');
      expect(host.members.single.isHost, isTrue);
      await a.join('127.0.0.1', host.port, '012345', username: 'Zoë 🎵');
      await b.join('127.0.0.1', host.port, '012345', username: 'Zoë 🎵');
      expect(a.roomName, 'Sunset 🌅 sessions');
      expect(b.roomName, a.roomName);
      expect(a.members.map((m) => m.name), ['Razeem', 'Zoë 🎵', 'Zoë 🎵']);
      expect(
        b.members.map((m) => m.toJson()),
        host.members.map((m) => m.toJson()),
      );
      expect(a.localMemberId, isNot(b.localMemberId));
      final oldId = a.localMemberId;
      final left = b.changes.stream.firstWhere((_) => b.count == 2);
      await a.close();
      await left.timeout(const Duration(seconds: 2));
      expect(b.members.any((m) => m.id == oldId), isFalse);
      expect(a.members, isEmpty);
      expect(a.roomName, isNull);
      await a.join('127.0.0.1', host.port, '012345', username: 'Zoë 🎵');
      expect(a.localMemberId, isNot(oldId));
      expect(a.members.length, 3);
    },
  );

  test(
    'empty and oversized room identity is rejected before opening a room',
    () async {
      final host = _room();
      addTearDown(host.close);
      await expectLater(
        host.create('123456', username: ' ', name: 'Sunset'),
        throwsFormatException,
      );
      await expectLater(
        host.create('123456', username: 'Host', name: 'x' * 37),
        throwsFormatException,
      );
      expect(host.connected, isFalse);
      expect(
        () => roomText('x' * 25, limit: 24, label: 'Username'),
        throwsFormatException,
      );
      expect(
        () => roomText('a\u0000b', limit: 24, label: 'Username'),
        throwsFormatException,
      );
    },
  );
  test(
    'two listeners authenticate, synchronize clocks, receive sound and close',
    () async {
      final host = _room(), a = _room(), b = _room();
      addTearDown(() async {
        await a.close();
        await b.close();
        await host.close();
      });
      await host.create('123456', username: 'Razeem', name: 'Sunset sessions');
      await a.join('127.0.0.1', host.port, '123456', username: 'a');
      await b.join('127.0.0.1', host.port, '123456', username: 'b');
      expect(a.clock.ready, isTrue);
      expect(b.clock.ready, isTrue);
      expect(host.count, 3);
      final gotA = Completer<AudioFrame>(), gotB = Completer<AudioFrame>();
      a.onAudio = gotA.complete;
      b.onAudio = gotB.complete;
      final pcm = Uint8List(frameBytes)..[0] = 99;
      host.broadcast(AudioFrame(1, host.clock.now + 450000, pcm));
      expect(
        (await gotA.future.timeout(const Duration(seconds: 2))).pcm[0],
        99,
      );
      expect(
        (await gotB.future.timeout(const Duration(seconds: 2))).pcm[0],
        99,
      );
      expect(a.audioFramesReceived, 1);
      expect(b.audioFramesReceived, 1);
      final ended = Completer<String>();
      a.onEnded = ended.complete;
      await host.close();
      await ended.future.timeout(const Duration(seconds: 2));
      expect(a.connected, isFalse);
      expect(a.audioFramesReceived, 0);
    },
  );
  test(
    'capture state reaches existing and late listeners and resets on close',
    () async {
      final host = _room(), a = _room(), b = _room();
      addTearDown(() async {
        await a.close();
        await b.close();
        await host.close();
      });
      await host.create('012345', username: 'Razeem', name: 'Sunset sessions');
      host.setSource('device');
      host.setCaptureStatus('waiting');
      await a.join('127.0.0.1', host.port, '012345', username: 'a');
      expect(a.source, 'device');
      expect(a.captureStatus, 'waiting');
      final live = a.changes.stream.firstWhere(
        (_) => a.captureStatus == 'live',
      );
      host.setCaptureStatus('live');
      await live.timeout(const Duration(seconds: 2));
      final silent = a.changes.stream.firstWhere(
        (_) => a.captureStatus == 'silent',
      );
      host.setCaptureStatus('silent');
      await silent.timeout(const Duration(seconds: 2));
      await b.join('127.0.0.1', host.port, '012345', username: 'b');
      expect(b.captureStatus, 'silent');
      host.setCaptureStatus('invalid');
      expect(host.captureStatus, 'silent');
      await a.close();
      expect(a.captureStatus, 'idle');
      await host.close();
      expect(host.captureStatus, 'idle');
    },
  );
  test('wrong code is rejected', () async {
    final host = _room(), guest = _room();
    addTearDown(() async {
      await guest.close();
      await host.close();
    });
    await host.create('123456', username: 'Razeem', name: 'Sunset sessions');
    await expectLater(
      guest.join('127.0.0.1', host.port, '999999', username: 'guest'),
      throwsA(anything),
    );
    expect(host.count, 1);
  });

  test('creator clock replies contain receive and send timestamps', () async {
    final host = _room();
    await host.create('123456', username: 'Host', name: 'Timing room');
    final rawPeer = await WebSocket.connect(
      'ws://127.0.0.1:${host.port}/room',
      headers: {
        'x-beatrazeem-audio-version': SecureRoomSocket.version,
        'x-beatrazeem-code': '123456',
      },
    );
    final peer = await SecureRoomSocket.establish(
      rawPeer,
      roomCode: '123456',
      isHost: false,
      verify: (_) async => true,
    );
    addTearDown(() async {
      await peer.close();
      await host.close();
    });
    final pong = peer.stream
        .where((message) => message is String)
        .map((message) => jsonDecode(message as String) as Map<String, dynamic>)
        .firstWhere((message) => message['type'] == 'pong');
    peer.add(jsonEncode({'type': 'ping', 'sent': 123}));
    final reply = await pong.timeout(const Duration(seconds: 2));
    expect(reply['sent'], 123);
    expect(reply['hostReceived'], isA<int>());
    expect(reply['host'], greaterThanOrEqualTo(reply['hostReceived'] as int));
  });

  test(
    'plaintext hosts are rejected instead of silently downgrading security',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final raw = await WebSocketTransformer.upgrade(request);
        raw.listen((_) {
          raw.add(jsonEncode({'type': 'welcome', 'room': 'Unencrypted'}));
        });
      });
      final guest = _room();
      addTearDown(() async {
        await guest.close();
        await server.close(force: true);
      });
      await expectLater(
        guest.join('127.0.0.1', server.port, '123456', username: 'Guest'),
        throwsA(anything),
      );
      expect(guest.connected, isFalse);
    },
  );

  test(
    'join fails cleanly when a host never establishes audio timing',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <SecureRoomSocket>[];
      server.listen((request) async {
        final raw = await WebSocketTransformer.upgrade(request);
        final socket = await SecureRoomSocket.establish(
          raw,
          roomCode: '123456',
          isHost: true,
          verify: (_) async => true,
        );
        sockets.add(socket);
        socket.listen((_) {}); // Connected but never answers clock requests.
      });
      final guest = _room();
      addTearDown(() async {
        await guest.close();
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      });
      await expectLater(
        guest.join('127.0.0.1', server.port, '123456', username: 'Guest'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Could not synchronize'),
          ),
        ),
      );
      expect(guest.connected, isFalse);
      expect(guest.clock.ready, isFalse);
      expect(guest.code, isNull);
    },
  );
}

class _AudioListener {
  _AudioListener(this.socket) {
    socket.listen((message) {
      if (message is String) {
        if ((jsonDecode(message) as Map)['type'] == 'welcome' &&
            !_welcome.isCompleted) {
          _welcome.complete();
        }
        return;
      }
      if (message is! List<int>) return;
      frames.add(AudioFrame.decode(message)!);
      if (!_received.isClosed) _received.add(null);
    });
  }

  final _welcome = Completer<void>();
  final SecureRoomSocket socket;
  final List<AudioFrame> frames = [];
  final StreamController<void> _received = StreamController.broadcast(
    sync: true,
  );

  static Future<_AudioListener> connect(RoomTransport host) async {
    final raw = await WebSocket.connect(
      'ws://127.0.0.1:${host.port}/room',
      headers: {
        'x-beatrazeem-audio-version': SecureRoomSocket.version,
        'x-beatrazeem-code': '123456',
        'x-beatrazeem-audio-ack': '1',
      },
    );
    final socket = await SecureRoomSocket.establish(
      raw,
      roomCode: '123456',
      isHost: false,
      verify: (_) async => true,
    );
    final listener = _AudioListener(socket);
    await listener._welcome.future.timeout(const Duration(seconds: 2));
    return listener;
  }

  Future<void> waitForCount(int count) async {
    if (frames.length >= count) return;
    await _received.stream
        .firstWhere((_) => frames.length >= count)
        .timeout(const Duration(seconds: 2));
  }

  void acknowledge(int sequence) {
    socket.add(jsonEncode({'type': 'audioAck', 'sequence': sequence}));
  }

  Future<void> close() async {
    await socket.close();
    await _received.close();
  }
}
