import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'protocol.dart';
import 'room_member.dart';
import 'clock_link.dart';

/// Local-network transport. Room audio stays on the LAN; no upload server.
class RoomTransport {
  final RoomClock clock = RoomClock();
  late final ClockLink _clockLink = ClockLink(clock);
  bool get hasDirectClock => _clockLink.healthy;
  final StreamController<void> changes = StreamController.broadcast();
  void Function(AudioFrame)? onAudio;
  void Function(String)? onSource;
  void Function(String)? onEnded;
  HttpServer? _server;
  WebSocket? _host;
  final Map<WebSocket, RoomMember> _clients = {};
  final Map<WebSocket, _PeerAudioQueue> _audioQueues = {};
  int? _lastBroadcastSequence;
  String _hostName = '';
  int _nextMember = 0;
  String? roomName;
  String? localMemberId;
  List<RoomMember> members = const [];
  Timer? _ping;
  final Set<int> _pendingPings = {};
  String? code;
  String source = 'idle';
  String captureStatus = 'idle';
  int audioFramesReceived = 0;
  bool get isHost => _server != null;
  bool get connected => isHost || _host != null;
  int get port => _server?.port ?? 0;
  int count = 1;
  bool _closing = false;

  Future<void> create(
    String roomCode, {
    required String username,
    required String name,
  }) async {
    final hostName = roomText(username, limit: 24, label: 'Username');
    final title = roomText(name, limit: 36, label: 'Room name');
    await close();
    if (!validRoomCode(roomCode)) {
      throw const FormatException('Use a 6-digit code.');
    }
    code = roomCode;
    _hostName = hostName;
    roomName = title;
    localMemberId = 'host';
    _nextMember = 0;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    try {
      await _clockLink.serve(_server!.port, roomCode);
    } catch (_) {
      /* TCP fallback remains available. */
    }
    _server!.listen((request) async {
      if (request.headers.value('x-beatrazeem-audio-version') != '2') {
        request.response.statusCode = HttpStatus.upgradeRequired;
        await request.response.close();
        return;
      }
      if (request.headers.value('x-beatrazeem-code') != code ||
          _clients.length >= 8 ||
          !WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      try {
        final encodedName = request.headers.value('x-beatrazeem-name');
        if (encodedName != null && encodedName.length > 512) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }
        final name = encodedName == null
            ? 'Listener'
            : roomText(
                Uri.decodeComponent(encodedName),
                limit: 24,
                label: 'Username',
              );
        final socket = await WebSocketTransformer.upgrade(request);
        if (_server == null || _clients.length >= 8) {
          await socket.close();
          return;
        }
        socket.pingInterval = const Duration(seconds: 5);
        final member = RoomMember(id: 'member-${++_nextMember}', name: name);
        _clients[socket] = member;
        if (request.headers.value('x-beatrazeem-audio-ack') == '1') {
          _audioQueues[socket] = _PeerAudioQueue();
        }
        socket.listen(
          (message) {
            final receivedAt = clock.now;
            if (message is! String || message.length > 4096) return;
            try {
              final body = jsonDecode(message) as Map<String, dynamic>;
              if (body['type'] == 'ping' && body['sent'] is int) {
                socket.add(
                  jsonEncode({
                    'type': 'pong',
                    'sent': body['sent'],
                    'host': clock.now,
                    'hostReceived': receivedAt,
                  }),
                );
              } else if (body['type'] == 'audioAck' &&
                  body['sequence'] is int) {
                final pending = _audioQueues[socket];
                final sequence = body['sequence'] as int;
                final acknowledged = pending?.inFlight.indexOf(sequence) ?? -1;
                if (acknowledged >= 0) {
                  // WebSocket messages and their ACKs are ordered. Match the
                  // first occurrence so a restarted stream may reuse numbers
                  // while the preceding stream's ACKs are still arriving.
                  pending!.inFlight.removeRange(0, acknowledged + 1);
                  _drainAudio(socket, pending);
                }
              } else if (body['type'] == 'rename' && body['name'] is String) {
                final current = _clients[socket];
                if (current == null) return;
                final name = roomText(
                  body['name'] as String,
                  limit: 24,
                  label: 'Username',
                );
                // A connection may change only its own display name, not its ID or role.
                _clients[socket] = RoomMember(id: current.id, name: name);
                _roster();
              }
            } catch (_) {
              /* Ignore malformed peer control messages. */
            }
          },
          onDone: () => _remove(socket),
          onError: (_) => _remove(socket),
        );
        socket.add(
          jsonEncode({'type': 'welcome', 'id': member.id, 'room': roomName}),
        );
        socket.add(jsonEncode({'type': 'source', 'value': source}));
        socket.add(jsonEncode({'type': 'capture', 'value': captureStatus}));
        _roster();
      } catch (_) {
        try {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
        } catch (_) {
          /* Peer left during upgrade. */
        }
      }
    });
    _roster();
  }

  Future<void> join(
    String address,
    int port,
    String roomCode, {
    required String username,
  }) async {
    final name = roomText(username, limit: 24, label: 'Username');
    await close();
    if (!validRoomCode(roomCode)) {
      throw const FormatException('Use a 6-digit code.');
    }
    final uri = Uri(scheme: 'ws', host: address, port: port, path: '/room');
    WebSocket socket;
    try {
      socket = await WebSocket.connect(
        uri.toString(),
        headers: {
          'x-beatrazeem-code': roomCode,
          'x-beatrazeem-name': Uri.encodeComponent(name),
          'x-beatrazeem-audio-ack': '1',
          'x-beatrazeem-audio-version': '2',
        },
      ).timeout(const Duration(seconds: 8));
    } on WebSocketException catch (error) {
      if (error.httpStatusCode == HttpStatus.upgradeRequired) {
        throw StateError(
          'Update Beatrazeem on every phone, then create and join the room again.',
        );
      }
      rethrow;
    }
    _host = socket;
    code = roomCode;
    try {
      await _clockLink.connect(address, port, roomCode);
    } catch (_) {
      /* Older rooms and restricted networks use TCP timing. */
    }
    socket.pingInterval = const Duration(seconds: 5);
    socket.listen(
      (message) {
        final receivedAt = clock.now;
        if (_host != socket) return;
        if (message is List<int>) {
          final frame = AudioFrame.decode(message);
          if (frame != null) {
            socket.add(
              jsonEncode({'type': 'audioAck', 'sequence': frame.sequence}),
            );
            audioFramesReceived++;
            if (clock.ready) onAudio?.call(frame);
            if (audioFramesReceived % 10 == 1) _notify();
          }
          return;
        }
        if (message is! String || message.length > 4096) return;
        try {
          final data = jsonDecode(message) as Map<String, dynamic>;
          switch (data['type']) {
            case 'welcome':
              final id = data['id'] as String;
              final title = roomText(
                data['room'] as String,
                limit: 36,
                label: 'Room name',
              );
              if (id.isEmpty || id.length > 48) break;
              localMemberId = id;
              roomName = title;
              _notify();
            case 'pong':
              if (data['sent'] is int &&
                  data['host'] is int &&
                  _pendingPings.remove(data['sent'])) {
                final received = data['hostReceived'];
                if (!_clockLink.healthy) {
                  clock.sample(
                    data['sent'] as int,
                    received is int ? received : data['host'] as int,
                    receivedAt,
                    hostSent: received is int ? data['host'] as int : null,
                  );
                }
                _notify();
              }
            case 'source':
              final nextSource = data['value'] as String;
              if (source != nextSource) audioFramesReceived = 0;
              source = nextSource;
              onSource?.call(source);
              _notify();
            case 'roster':
              final total = data['count'] as int;
              if (total < 1 || total > 9) break;
              if (data['members'] is List) {
                final raw = data['members'] as List;
                if (raw.length != total) break;
                final roster = raw
                    .map(
                      (item) => RoomMember.fromJson(
                        Map<String, dynamic>.from(item as Map),
                      ),
                    )
                    .toList();
                if (roster.map((member) => member.id).toSet().length != total ||
                    roster.where((member) => member.isHost).length != 1) {
                  break;
                }
                members = List.unmodifiable(roster);
              }
              count = total;
              _notify();
            case 'capture':
              final value = data['value'];
              if (captureStates.contains(value)) {
                captureStatus = value as String;
                _notify();
              }
          }
        } catch (_) {
          /* Ignore malformed packets. */
        }
      },
      onDone: () => _disconnected(socket),
      onError: (_) => _disconnected(socket),
    );
    // Get a reliable clock before reporting a successful join. Keep trying
    // briefly on a busy LAN rather than silently joining with no audio clock.
    for (var i = 0; i < 30 && (i < 6 || !clock.ready); i++) {
      if (_host != socket) break;
      _sendPing();
      await Future<void>.delayed(Duration(milliseconds: i < 6 ? 50 : 100));
    }
    if (_host != socket) {
      throw StateError(
        'The room disconnected while synchronizing. Join again.',
      );
    }
    if (!clock.ready) {
      await close();
      throw StateError(
        'Could not synchronize with the creator. Check the Wi-Fi connection and join again.',
      );
    }
    _ping = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _sendPing(),
    );
    _notify();
  }

  void _sendPing() {
    final host = _host;
    if (host == null || host.readyState != WebSocket.open) return;
    _clockLink.ping();
    if (_clockLink.healthy) return;
    final sent = clock.now;
    _pendingPings.removeWhere((previous) => sent - previous > 2000000);
    _pendingPings.add(sent);
    host.add(jsonEncode({'type': 'ping', 'sent': sent}));
  }

  Future<void> resynchronize() async {
    if (isHost) return;
    final host = _host;
    if (host == null) throw StateError('Join a room first.');
    clock.reset();
    _pendingPings.clear();
    _clockLink.resetMeasurements();
    for (var i = 0; i < 30 && !clock.ready; i++) {
      if (_host != host) throw StateError('The room disconnected. Join again.');
      _sendPing();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!clock.ready) {
      throw StateError(
        'Timing could not settle. Check the hotspot connection and try again.',
      );
    }
    _notify();
  }

  void rename(String value) {
    final name = roomText(value, limit: 24, label: 'Username');
    if (isHost) {
      _hostName = name;
      _roster();
    } else {
      final socket = _host;
      if (socket != null && socket.readyState == WebSocket.open) {
        socket.add(jsonEncode({'type': 'rename', 'name': name}));
      }
    }
  }

  void broadcast(AudioFrame frame) {
    if (_lastBroadcastSequence != null &&
        frame.sequence <= _lastBroadcastSequence!) {
      _clearUnsentAudio();
    }
    _lastBroadcastSequence = frame.sequence;
    final now = clock.now;
    if (frame.playAt + frame.durationUs <= now) return;
    final packet = frame.encode();
    for (final socket in _clients.keys.toList()) {
      if (socket.readyState != WebSocket.open) continue;
      final pending = _audioQueues[socket];
      if (pending == null) {
        socket.add(packet);
        continue;
      }
      pending.unsent.removeWhere(
        (queued) => queued.frame.playAt + queued.frame.durationUs <= now,
      );
      pending.unsent.add((frame: frame, packet: packet));
      // Capture callbacks can arrive in a burst. Keep still-useful audio until
      // an ACK frees a slot, while bounding both memory and queued audio time.
      var queuedUs = pending.unsent.fold<int>(
        0,
        (duration, queued) => duration + queued.frame.durationUs,
      );
      while (pending.unsent.length > 10 || queuedUs > playoutDelayUs) {
        queuedUs -= pending.unsent.removeAt(0).frame.durationUs;
      }
      _drainAudio(socket, pending);
    }
  }

  void _drainAudio(WebSocket socket, _PeerAudioQueue pending) {
    if (socket.readyState != WebSocket.open) return;
    final now = clock.now;
    while (pending.unsent.isNotEmpty && pending.inFlight.length < 8) {
      final queued = pending.unsent.removeAt(0);
      if (queued.frame.playAt + queued.frame.durationUs <= now) continue;
      pending.inFlight.add(queued.frame.sequence);
      socket.add(queued.packet);
    }
  }

  void _clearUnsentAudio() {
    for (final pending in _audioQueues.values) {
      pending.unsent.clear();
      // Already-sent audio cannot be retracted from TCP. Retain its credit
      // until acknowledged, including across source and sequence changes.
    }
  }

  void setSource(String value) {
    source = value;
    _clearUnsentAudio();
    _lastBroadcastSequence = null;
    for (final socket in _clients.keys.toList()) {
      if (socket.readyState == WebSocket.open) {
        socket.add(jsonEncode({'type': 'source', 'value': value}));
      }
    }
    _notify();
  }

  static const captureStates = {'idle', 'waiting', 'live', 'silent', 'noData'};
  void setCaptureStatus(String value) {
    if (!isHost || !captureStates.contains(value) || captureStatus == value) {
      return;
    }
    captureStatus = value;
    for (final socket in _clients.keys.toList()) {
      if (socket.readyState == WebSocket.open) {
        socket.add(jsonEncode({'type': 'capture', 'value': value}));
      }
    }
    _notify();
  }

  void _roster() {
    count = _clients.length + 1;
    members = List.unmodifiable([
      RoomMember(id: 'host', name: _hostName, isHost: true),
      ..._clients.values,
    ]);
    for (final socket in _clients.keys.toList()) {
      if (socket.readyState == WebSocket.open) {
        socket.add(
          jsonEncode({
            'type': 'roster',
            'count': count,
            'members': members.map((member) => member.toJson()).toList(),
          }),
        );
      }
    }
    _notify();
  }

  void _remove(WebSocket socket) {
    _audioQueues.remove(socket);
    final removed = _clients.remove(socket);
    if (!_closing && isHost && removed != null) _roster();
  }

  void _disconnected(WebSocket socket) {
    if (_host != socket || _closing) return;
    _host = null;
    code = null;
    roomName = null;
    localMemberId = null;
    members = const [];
    source = 'idle';
    count = 1;
    captureStatus = 'idle';
    audioFramesReceived = 0;
    _ping?.cancel();
    _clockLink.close();
    clock.reset();
    _pendingPings.clear();
    _notify();
    onEnded?.call('The creator ended the room or the connection was lost.');
  }

  void _notify() {
    if (!changes.isClosed) changes.add(null);
  }

  Future<void> close() async {
    _closing = true;
    _clockLink.close();
    _ping?.cancel();
    _ping = null;
    _pendingPings.clear();
    final host = _host;
    _host = null;
    await host?.close();
    for (final socket in _clients.keys.toList()) {
      await socket.close();
    }
    _clients.clear();
    _audioQueues.clear();
    _lastBroadcastSequence = null;
    await _server?.close(force: true);
    _server = null;
    code = null;
    roomName = null;
    localMemberId = null;
    members = const [];
    source = 'idle';
    count = 1;
    clock.reset();
    captureStatus = 'idle';
    audioFramesReceived = 0;
    _closing = false;
    _notify();
  }
}

class _PeerAudioQueue {
  final List<int> inFlight = [];
  final List<({AudioFrame frame, List<int> packet})> unsent = [];
}
