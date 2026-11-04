import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/core/discovery_limiter.dart';
import 'package:beatrazeem/core/direct_discovery.dart';
import 'package:beatrazeem/core/transport.dart';

void main() {
  test('eight different listeners can discover together', () {
    final limiter = DiscoveryLimiter(nowMs: () => 0);
    for (var i = 0; i < 8; i++) {
      expect(limiter.admit('phone-$i'), 0);
      limiter.recordResult('phone-$i', matched: true);
    }
  });
  test('per-source budget survives successful guesses and refills', () {
    var now = 0;
    final limiter = DiscoveryLimiter(nowMs: () => now);
    for (var i = 0; i < 6; i++) {
      expect(limiter.admit('phone'), 0);
      limiter.recordResult('phone', matched: true);
    }
    expect(limiter.admit('phone'), 5);
    expect(limiter.admit('other'), 0);
    now = 5000;
    expect(limiter.admit('phone'), 0);
  });
  test('rotating sources still share the global budget', () {
    var now = 0;
    final limiter = DiscoveryLimiter(nowMs: () => now);
    for (var i = 0; i < 32; i++) {
      expect(limiter.admit('source-$i'), 0);
    }
    expect(limiter.admit('new-source'), 1);
    now = 500;
    expect(limiter.admit('new-source'), 0);
  });
  test('failed guesses back off, cap at 30 seconds and recover', () {
    var now = 0;
    final limiter = DiscoveryLimiter(nowMs: () => now);
    for (var i = 0; i < 12; i++) {
      var retry = limiter.admit('attacker');
      while (retry > 0) {
        expect(retry, lessThanOrEqualTo(30));
        now += retry * 1000;
        retry = limiter.admit('attacker');
      }
      limiter.recordResult('attacker', matched: false);
    }
    expect(limiter.admit('attacker'), 30);
    expect(limiter.failedAttempts, 12);
    expect(limiter.throttledRequests, greaterThan(0));
    now += 30000;
    expect(limiter.admit('attacker'), 0);
  });
  test('source bookkeeping is bounded and expires', () {
    var now = 0;
    final limiter = DiscoveryLimiter(nowMs: () => now);
    for (var i = 0; i < 1000; i++) {
      limiter.admit('source-$i');
    }
    expect(limiter.trackedSources, DiscoveryLimiter.maxSources);
    expect(limiter.admit('fresh'), 30);
    now = 300000;
    expect(limiter.admit('fresh'), 0);
    expect(limiter.trackedSources, 1);
  });

  Future<(int, String?, String)> probe(int port, String code) async {
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/beatrazeem/room'),
      );
      request.headers.set('x-beatrazeem-code', code);
      final response = await request.close();
      final bytes = <int>[];
      await for (final part in response) {
        bytes.addAll(part);
      }
      return (
        response.statusCode,
        response.headers.value('retry-after'),
        String.fromCharCodes(bytes),
      );
    } finally {
      client.close(force: true);
    }
  }

  test(
    'HTTP guesses across new connections are throttled before code lookup',
    () async {
      final discovery = DirectRoomDiscovery(discoveryPort: 0);
      addTearDown(discovery.stop);
      await discovery.advertise('123456', 23456);
      for (var i = 0; i < 3; i++) {
        expect((await probe(discovery.port, '999999')).$1, 404);
      }
      final limited = await probe(discovery.port, '123456');
      expect(limited.$1, 429);
      expect(int.parse(limited.$2!), inInclusiveRange(1, 30));
      expect(limited.$3, isEmpty);
      expect(discovery.failedDiscoveryAttempts, 3);
      expect(discovery.throttledDiscoveryRequests, 1);
      await discovery.stop();
      await discovery.advertise('654321', 34567);
      expect((await probe(discovery.port, '654321')).$1, 200);
      expect(discovery.failedDiscoveryAttempts, 0);
    },
  );
  test(
    'finder respects server Retry-After instead of probing every 300ms',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final watch = Stopwatch()..start();
      final received = <int>[];
      server.listen((request) async {
        received.add(watch.elapsedMilliseconds);
        request.response.statusCode = 429;
        request.response.headers.set('retry-after', '1');
        await request.response.close();
      });
      final discovery = DirectRoomDiscovery(discoveryPort: server.port);
      addTearDown(() async {
        await discovery.stop();
        await server.close(force: true);
      });
      expect(
        await discovery.find('123456', [
          '127.0.0.1',
        ], timeout: const Duration(milliseconds: 1600)),
        isNull,
      );
      expect(received.length, 2);
      expect(received[1] - received[0], greaterThanOrEqualTo(1000));
    },
  );
  test(
    'discovered port cannot grant room access without host approval',
    () async {
      final host = RoomTransport(); // Missing verifier must deny admission.
      final listener = RoomTransport()..onVerifyPeer = (_) async => true;
      final discovery = DirectRoomDiscovery(discoveryPort: 0);
      addTearDown(() async {
        await listener.close();
        await discovery.stop();
        await host.close();
      });
      await host.create('123456', username: 'Creator', name: 'Private room');
      await discovery.advertise('123456', host.port);
      final response = await probe(discovery.port, '123456');
      expect(response.$1, 200);
      await expectLater(
        listener.join('127.0.0.1', host.port, '123456', username: 'Unapproved'),
        throwsStateError,
      );
      expect(listener.connected, isFalse);
      expect(host.members.length, 1);
    },
  );
}
