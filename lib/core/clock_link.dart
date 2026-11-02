import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'protocol.dart';

/// Clock requests bypass the ordered audio stream, so a congested audio queue
/// cannot bias the time exchange. TCP clock replies remain a fallback.
class ClockLink {
  ClockLink(this.clock);
  final RoomClock clock;
  RawDatagramSocket? _socket;
  InternetAddress? _host;
  int _port = 0;
  String _code = '';
  int? _lastReply;
  final Set<int> _pending = {};
  bool get healthy => _lastReply != null && clock.now - _lastReply! < 1500000;

  Future<void> serve(int port, String code) async {
    close();
    _code = code;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    _socket = socket;
    socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        Datagram? packet;
        while ((packet = socket.receive()) != null) {
          final data = packet!;
          final received = clock.now;
          final body = _decode(data.data);
          if (body?['type'] != 'clockPing' ||
              body?['code'] != _code ||
              body?['sent'] is! int) {
            continue;
          }
          socket.send(
            utf8.encode(
              jsonEncode({
                'type': 'clockPong',
                'code': _code,
                'sent': body!['sent'],
                'received': received,
                'host': clock.now,
              }),
            ),
            data.address,
            data.port,
          );
        }
      },
      onError: (Object _) {
        close();
      },
    );
  }

  Future<void> connect(String address, int port, String code) async {
    close();
    _host = InternetAddress(address);
    _port = port;
    _code = code;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket = socket;
    socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        Datagram? packet;
        while ((packet = socket.receive()) != null) {
          final data = packet!;
          final now = clock.now;
          if (data.address.address != _host?.address || data.port != _port) {
            continue;
          }
          final body = _decode(data.data);
          if (body?['type'] != 'clockPong' ||
              body?['code'] != _code ||
              body?['sent'] is! int ||
              body?['received'] is! int ||
              body?['host'] is! int) {
            continue;
          }
          final sent = body!['sent'] as int;
          if (!_pending.remove(sent)) continue;
          final hostReceived = body['received'] as int,
              hostSent = body['host'] as int;
          final elapsed = now - sent, processing = hostSent - hostReceived;
          if (elapsed < 0 ||
              processing < 0 ||
              elapsed - processing < 0 ||
              elapsed - processing > 250000) {
            continue;
          }
          clock.sample(sent, hostReceived, now, hostSent: hostSent);
          _lastReply = now;
        }
      },
      onError: (Object _) {
        close();
      },
    );
  }

  void ping() {
    final socket = _socket, host = _host;
    if (socket == null || host == null) return;
    final sent = clock.now;
    _pending.removeWhere((old) => sent - old > 1500000);
    _pending.add(sent);
    try {
      socket.send(
        utf8.encode(
          jsonEncode({'type': 'clockPing', 'code': _code, 'sent': sent}),
        ),
        host,
        _port,
      );
    } catch (_) {
      close();
    }
  }

  void resetMeasurements() {
    _pending.clear();
    _lastReply = null;
  }

  Map<String, dynamic>? _decode(List<int> bytes) {
    if (bytes.length > 512) return null;
    try {
      final body = jsonDecode(utf8.decode(bytes));
      return body is Map<String, dynamic> ? body : null;
    } catch (_) {
      return null;
    }
  }

  void close() {
    _socket?.close();
    _socket = null;
    _pending.clear();
    _host = null;
    _lastReply = null;
  }
}
