import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'protocol.dart';

/// Unicast discovery works on the creator's hotspot without mDNS multicast.
class DirectRoomDiscovery {
  DirectRoomDiscovery({this.discoveryPort = 45873});
  final int discoveryPort;
  HttpServer? _server;
  final Set<HttpClient> _clients = {};
  int _search = 0;
  int get port => _server?.port ?? discoveryPort;

  Future<void> advertise(String code, int roomPort) async {
    if (!validRoomCode(code) || roomPort < 1 || roomPort > 65535) {
      throw const FormatException('Invalid room address.');
    }
    await _server?.close(force: true);
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
    );
    _server = server;
    server.idleTimeout = const Duration(seconds: 3);
    server.listen((request) async {
      try {
        if (request.method != 'GET' ||
            request.uri.path != '/beatrazeem/room' ||
            request.headers.value('x-beatrazeem-code') != code) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'service': 'beatrazeem',
              'code': code,
              'port': roomPort,
            }),
          );
        }
        await request.response.close();
      } catch (_) {
        /* A probing device disconnected. */
      }
    });
  }

  Future<(String, int)?> find(
    String code,
    List<String> gateways, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!validRoomCode(code)) {
      throw const FormatException('Enter exactly 6 digits.');
    }
    final search = ++_search;
    final addresses = gateways
        .where(
          (value) =>
              InternetAddress.tryParse(value)?.type == InternetAddressType.IPv4,
        )
        .toSet()
        .take(8)
        .toList();
    if (addresses.isEmpty) return null;
    final watch = Stopwatch()..start();
    while (search == _search && watch.elapsed < timeout) {
      final found = Completer<(String, int)?>();
      var remaining = addresses.length;
      for (final address in addresses) {
        unawaited(
          _probe(address, code).then((port) {
            if (port != null && !found.isCompleted) {
              found.complete((address, port));
            }
            if (--remaining == 0 && !found.isCompleted) found.complete(null);
          }),
        );
      }
      final result = await found.future;
      if (search != _search) return null;
      if (result != null) return result;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return null;
  }

  Future<int?> _probe(String address, String code) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 900);
    client.findProxy = (_) => 'DIRECT';
    _clients.add(client);
    try {
      return await (() async {
        final request = await client.getUrl(
          Uri(
            scheme: 'http',
            host: address,
            port: discoveryPort,
            path: '/beatrazeem/room',
          ),
        );
        request.followRedirects = false;
        request.headers.set('x-beatrazeem-code', code);
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) return null;
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 1024) return null;
          bytes.addAll(chunk);
        }
        final body = jsonDecode(utf8.decode(bytes));
        if (body is! Map ||
            body['service'] != 'beatrazeem' ||
            body['code'] != code) {
          return null;
        }
        final port = body['port'];
        return port is int && port > 0 && port <= 65535 ? port : null;
      })().timeout(const Duration(milliseconds: 1200));
    } catch (_) {
      return null;
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  void cancelSearch() {
    _search++;
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    _clients.clear();
  }

  Future<void> stop() async {
    cancelSearch();
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}
