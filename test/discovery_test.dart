import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/core/direct_discovery.dart';
import 'package:beatrazeem/core/discovery.dart';
import 'package:beatrazeem/core/local_network.dart';
import 'package:beatrazeem/core/transport.dart';

class TestNetwork extends LocalNetwork {
  bool bound = false;
  @override
  Future<List<String>> prepareListener() async {
    bound = true;
    return ['127.0.0.1'];
  }

  @override
  Future<void> release() async {
    bound = false;
  }
}

void main() {
  test('creator hotspot joins by code without any multicast support', () async {
    final host = RoomTransport(), listener = RoomTransport();
    final endpoint = DirectRoomDiscovery(discoveryPort: 0);
    final network = TestNetwork();
    RoomDiscovery? discovery;
    addTearDown(() async {
      await discovery?.stop();
      await listener.close();
      await endpoint.stop();
      await host.close();
    });
    await host.create('012345', username: 'Creator', name: 'Hotspot room');
    await endpoint.advertise('012345', host.port);
    discovery = RoomDiscovery(
      direct: DirectRoomDiscovery(discoveryPort: endpoint.port),
      network: network,
      useMulticast: false,
    );
    final address = await discovery.find('012345');
    expect(address, ('127.0.0.1', host.port));
    expect(network.bound, isTrue);
    await listener.join(address.$1, address.$2, '012345', username: 'Listener');
    expect(listener.connected, isTrue);
    expect(listener.roomName, 'Hotspot room');
    expect(listener.hasDirectClock, isTrue);
    await discovery.stop();
    expect(network.bound, isFalse);
  });

  test('wrong code fails and releases the listener Wi-Fi binding', () async {
    final endpoint = DirectRoomDiscovery(discoveryPort: 0),
        network = TestNetwork();
    await endpoint.advertise('012345', 12345);
    final discovery = RoomDiscovery(
      direct: DirectRoomDiscovery(discoveryPort: endpoint.port),
      network: network,
      useMulticast: false,
      searchTimeout: const Duration(milliseconds: 180),
    );
    addTearDown(() async {
      await discovery.stop();
      await endpoint.stop();
    });
    await expectLater(discovery.find('999999'), throwsException);
    expect(network.bound, isFalse);
  });

  test('direct discovery retries after the creator opens their room', () async {
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    final endpoint = DirectRoomDiscovery(discoveryPort: port),
        finder = DirectRoomDiscovery(discoveryPort: port);
    addTearDown(() async {
      await finder.stop();
      await endpoint.stop();
    });
    final found = finder.find('123456', [
      '127.0.0.1',
    ], timeout: const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await endpoint.advertise('123456', 23456);
    expect(await found, ('127.0.0.1', 23456));
  });

  test(
    'a gateway response must identify Beatrazeem and match the requested code',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.write(
          jsonEncode({
            'service': 'beatrazeem',
            'code': '654321',
            'port': 34567,
          }),
        );
        await request.response.close();
      });
      final finder = DirectRoomDiscovery(discoveryPort: server.port);
      addTearDown(() async {
        await finder.stop();
        await server.close(force: true);
      });
      expect(
        await finder.find('123456', [
          '127.0.0.1',
        ], timeout: const Duration(milliseconds: 150)),
        isNull,
      );
    },
  );

  test('ending a creator room closes its direct discovery endpoint', () async {
    final endpoint = DirectRoomDiscovery(discoveryPort: 0);
    await endpoint.advertise('123456', 23456);
    final finder = DirectRoomDiscovery(discoveryPort: endpoint.port);
    await endpoint.stop();
    addTearDown(finder.stop);
    expect(
      await finder.find('123456', [
        '127.0.0.1',
      ], timeout: const Duration(milliseconds: 100)),
      isNull,
    );
  });
}
