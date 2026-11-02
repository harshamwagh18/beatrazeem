import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'protocol.dart';

/// Independent clock datagrams avoid audio queue delays. Secure rooms authorize
/// only keys exported from their verified link; clock replies use HMAC-SHA256.
class ClockLink {
  ClockLink(this.clock);
  final RoomClock clock;
  RawDatagramSocket? _socket;
  InternetAddress? _host;
  int _port = 0;
  String _code = '';
  bool _requireAuthentication = false;
  String? _sessionId;
  SecretKey? _authenticationKey;
  final Map<String, SecretKey> _authorized = {};
  final Map<String, int> _latestPing = {};
  int? _lastReply;
  final Set<int> _pending = {};
  bool get healthy => _lastReply != null && clock.now - _lastReply! < 1500000;

  void authorize(String id, SecretKey key) {
    if (_authorized.length < 8 || _authorized.containsKey(id)) {
      _authorized[id] = key;
      _latestPing.remove(id);
    }
  }

  void revoke(String id) {
    _authorized.remove(id);
    _latestPing.remove(id);
  }

  Future<void> serve(
    int port,
    String code, {
    bool requireAuthentication = false,
  }) async {
    close();
    _code = code;
    _requireAuthentication = requireAuthentication;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    _socket = socket;
    _listen(socket, (data, received) async {
      final body = await _decode(data.data);
      if (_socket != socket ||
          body?['type'] != 'clockPing' ||
          body?['code'] != _code ||
          body?['sent'] is! int) {
        return;
      }
      final id = body!['_session'] as String?;
      if (_requireAuthentication) {
        if (id == null || !_authorized.containsKey(id)) return;
        final sent = body['sent'] as int;
        if (sent < 0 || sent <= (_latestPing[id] ?? -1)) return;
        _latestPing[id] = sent;
      }
      final response = await _encode({
        'type': 'clockPong',
        'code': _code,
        'sent': body['sent'],
        'received': received,
        'host': clock.now,
      }, sessionId: id);
      if (_socket == socket) socket.send(response, data.address, data.port);
    });
  }

  Future<void> connect(
    String address,
    int port,
    String code, {
    String? sessionId,
    SecretKey? authenticationKey,
  }) async {
    close();
    _host = InternetAddress(address);
    _port = port;
    _code = code;
    _sessionId = sessionId;
    _authenticationKey = authenticationKey;
    _requireAuthentication = authenticationKey != null;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket = socket;
    _listen(socket, (data, now) async {
      if (data.address.address != _host?.address || data.port != _port) return;
      final body = await _decode(data.data);
      if (_socket != socket ||
          body?['type'] != 'clockPong' ||
          body?['code'] != _code ||
          body?['sent'] is! int ||
          body?['received'] is! int ||
          body?['host'] is! int) {
        return;
      }
      final sent = body!['sent'] as int;
      if (!_pending.remove(sent)) return;
      final hostReceived = body['received'] as int,
          hostSent = body['host'] as int;
      final elapsed = now - sent, processing = hostSent - hostReceived;
      if (elapsed < 0 ||
          processing < 0 ||
          elapsed - processing < 0 ||
          elapsed - processing > 250000) {
        return;
      }
      clock.sample(sent, hostReceived, now, hostSent: hostSent);
      _lastReply = now;
    });
  }

  /// Bound unauthenticated work before parsing or cryptography. Processing is
  /// serialized, capped at 200 datagrams/second and yields after 32 datagrams.
  /// Saturation makes the room use its encrypted TCP clock fallback.
  void _listen(
    RawDatagramSocket socket,
    Future<void> Function(Datagram, int) handle,
  ) {
    var reading = false, budget = 0, window = clock.now;
    socket.listen(
      (event) async {
        if (event != RawSocketEvent.read || reading || _socket != socket) {
          return;
        }
        reading = true;
        socket.readEventsEnabled = false;
        try {
          for (var i = 0; i < 32 && _socket == socket; i++) {
            final packet = socket.receive();
            if (packet == null) break;
            final now = clock.now;
            if (now - window >= 1000000) {
              window = now;
              budget = 0;
            }
            if (++budget > 200) continue;
            await handle(packet, now);
          }
        } catch (_) {
          if (_socket == socket) close();
        } finally {
          reading = false;
          if (_socket == socket) socket.readEventsEnabled = true;
        }
      },
      onError: (Object _) {
        if (_socket == socket) close();
      },
    );
  }

  void ping() async {
    final socket = _socket, host = _host;
    if (socket == null || host == null) return;
    final sent = clock.now;
    _pending.removeWhere((old) => sent - old > 1500000);
    _pending.add(sent);
    try {
      final packet = await _encode({
        'type': 'clockPing',
        'code': _code,
        'sent': sent,
      }, sessionId: _sessionId);
      if (_socket == socket) socket.send(packet, host, _port);
    } catch (_) {
      if (_socket == socket) close();
    }
  }

  void resetMeasurements() {
    _pending.clear();
    _lastReply = null;
  }

  Future<Map<String, dynamic>?> _decode(List<int> bytes) async {
    if (bytes.length > 1024) return null;
    try {
      final body = jsonDecode(utf8.decode(bytes));
      if (!_requireAuthentication) {
        return body is Map<String, dynamic> ? body : null;
      }
      if (body is! Map<String, dynamic> ||
          body['session'] is! String ||
          body['payload'] is! String ||
          body['mac'] is! String) {
        return null;
      }
      final id = body['session'] as String;
      final key = _authenticationKey != null && id == _sessionId
          ? _authenticationKey
          : _authorized[id];
      if (key == null) return null;
      final payload = base64Decode(body['payload'] as String);
      if (payload.length > 512) return null;
      final expected = await Hmac.sha256().calculateMac(
        payload,
        secretKey: key,
      );
      // Mac equality uses the library's constant-time bytes comparison.
      if (expected != Mac(base64Decode(body['mac'] as String))) return null;
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! Map<String, dynamic>) return null;
      decoded['_session'] = id;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<List<int>> _encode(
    Map<String, dynamic> body, {
    String? sessionId,
  }) async {
    final payload = utf8.encode(jsonEncode(body));
    if (!_requireAuthentication) return payload;
    final key = _authenticationKey ?? _authorized[sessionId];
    if (key == null || sessionId == null) {
      throw StateError('Unknown clock peer.');
    }
    final mac = await Hmac.sha256().calculateMac(payload, secretKey: key);
    return utf8.encode(
      jsonEncode({
        'session': sessionId,
        'payload': base64Encode(payload),
        'mac': base64Encode(mac.bytes),
      }),
    );
  }

  void close() {
    _socket?.close();
    _socket = null;
    _authorized.clear();
    _latestPing.clear();
    _authenticationKey = null;
    _sessionId = null;
    _requireAuthentication = false;
    _pending.clear();
    _host = null;
    _lastReply = null;
  }
}
