import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// A person must compare this value on the two physical phones before approving.
/// The room discovery code is deliberately not used as an encryption password.
class PeerVerification {
  const PeerVerification({
    required this.verificationCode,
    required this.isHost,
  });
  final String verificationCode;
  final bool isHost;
}

typedef VerifyPeer = Future<bool> Function(PeerVerification verification);

/// Ephemeral X25519 + HKDF-SHA256 + AES-256-GCM. A commit/reveal exchange
/// prevents choosing a public key after seeing the other party's reveal to
/// grind a matching short authentication string. Authentication is completed
/// by the human comparison on BOTH devices, before any personal data is sent.
class SecureRoomSocket {
  SecureRoomSocket._(
    this._socket,
    this._input,
    this._sendKey,
    this._receiveKey,
    this.verificationCode,
    this.clockId,
    this.clockKey,
  );
  static const version = '3';
  static const handshakeTimeout = Duration(seconds: 90);
  final WebSocket _socket;
  final StreamIterator<dynamic> _input;
  final SecretKey _sendKey, _receiveKey;
  final String verificationCode;
  final String clockId;
  final SecretKey clockKey;
  String? peerIdentity;
  final _events = StreamController<dynamic>();
  final _cipher = AesGcm.with256bits();
  Future<void> _sending = Future.value();
  int _sent = 0, _received = 0, _queued = 0;
  bool _closed = false;
  Stream<dynamic> get stream => _events.stream;
  int get readyState => _closed ? WebSocket.closed : _socket.readyState;

  static List<int> randomBytes(int count) {
    final random = Random.secure();
    return List.generate(count, (_) => random.nextInt(256));
  }

  static Future<SecureRoomSocket> establish(
    WebSocket socket, {
    required String roomCode,
    required bool isHost,
    required VerifyPeer? verify,
    String? username,
  }) async {
    final input = StreamIterator<dynamic>(socket);
    try {
      return await _handshake(
        socket,
        input,
        roomCode,
        isHost,
        verify,
        username,
      ).timeout(handshakeTimeout);
    } catch (_) {
      await socket.close(
        WebSocketStatus.policyViolation,
        'Verification failed',
      );
      unawaited(input.cancel());
      rethrow;
    }
  }

  static Future<SecureRoomSocket> _handshake(
    WebSocket socket,
    StreamIterator<dynamic> input,
    String roomCode,
    bool isHost,
    VerifyPeer? verify,
    String? username,
  ) async {
    if (verify == null) throw StateError('Device verification is required.');
    final x25519 = X25519();
    final pair = await x25519.newKeyPair();
    final public = (await pair.extractPublicKey()).bytes;
    final nonce = randomBytes(32);
    final reveal = [...public, ...nonce];
    final hash = Sha256();
    final commitment = (await hash.hash(reveal)).bytes;
    socket.add(
      jsonEncode({
        'type': 'commit',
        'version': version,
        'hash': base64Encode(commitment),
      }),
    );
    Future<Map<String, dynamic>> next(String type) async {
      if (!await input.moveNext()) throw StateError('Device disconnected.');
      final raw = input.current;
      if (raw is! String || raw.length > 1024) {
        throw const FormatException('Invalid verification message.');
      }
      final body = jsonDecode(raw) as Map<String, dynamic>;
      if (body['type'] != type || body['version'] != version) {
        throw const FormatException('Incompatible secure room.');
      }
      return body;
    }

    final remoteCommit = base64Decode((await next('commit'))['hash'] as String);
    if (remoteCommit.length != 32) {
      throw const FormatException('Invalid commitment.');
    }
    socket.add(
      jsonEncode({
        'type': 'reveal',
        'version': version,
        'value': base64Encode(reveal),
      }),
    );
    final remote = base64Decode((await next('reveal'))['value'] as String);
    if (remote.length != 64 ||
        !_equal((await hash.hash(remote)).bytes, remoteCommit)) {
      throw const FormatException('Device verification changed.');
    }
    final shared = await x25519.sharedSecretKey(
      keyPair: pair,
      remotePublicKey: SimplePublicKey(
        remote.sublist(0, 32),
        type: KeyPairType.x25519,
      ),
    );
    if ((await shared.extractBytes()).every((b) => b == 0)) {
      throw const FormatException('Invalid public key.');
    }
    final transcript = (await hash.hash([
      ...utf8.encode('Beatrazeem secure room v3:$roomCode:'),
      ...(isHost ? reveal : remote),
      ...(isHost ? remote : reveal),
    ])).bytes;
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    Future<SecretKey> derive(String label) => hkdf.deriveKey(
      secretKey: shared,
      nonce: transcript,
      info: utf8.encode(label),
    );
    final sas = await (await derive('human verification')).extractBytes();
    final number = ((sas[0] << 16) | (sas[1] << 8) | sas[2]) % 1000000;
    final code = number.toString().padLeft(6, '0');
    final hostKey = await derive('host to listener');
    final guestKey = await derive('listener to host');
    final result = SecureRoomSocket._(
      socket,
      input,
      isHost ? hostKey : guestKey,
      isHost ? guestKey : hostKey,
      code,
      base64UrlEncode(transcript.sublist(0, 12)),
      await derive('authenticated clock'),
    );
    final approved = await verify(
      PeerVerification(verificationCode: code, isHost: isHost),
    );
    if (!approved) throw StateError('Device verification was declined.');
    await result._write('verified');
    if (!await input.moveNext() ||
        await result._decode(input.current) != 'verified') {
      throw StateError('The other phone did not approve verification.');
    }
    if (isHost) {
      if (!await input.moveNext()) throw StateError('Device disconnected.');
      final rawIdentity = await result._decode(input.current);
      if (rawIdentity is! String || rawIdentity.length > 512) {
        throw const FormatException('Invalid identity.');
      }
      final identity = jsonDecode(rawIdentity) as Map<String, dynamic>;
      if (identity['type'] != 'identity' || identity['name'] is! String) {
        throw const FormatException('Invalid identity.');
      }
      result.peerIdentity = identity['name'] as String;
    } else {
      await result._write(
        jsonEncode({'type': 'identity', 'name': username ?? 'Listener'}),
      );
    }
    socket.pingInterval = const Duration(seconds: 5);
    unawaited(result._receive());
    return result;
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }

  Uint8List _counter(int value) =>
      Uint8List(8)..buffer.asByteData().setUint64(0, value);
  List<int> _nonce(int value) => [0, 0, 0, 0, ..._counter(value)];

  Future<void> _write(dynamic value) async {
    if (_closed) return;
    final plain = value is String
        ? [1, ...utf8.encode(value)]
        : [0, ...value as List<int>];
    if (plain.length > 65536 || _sent >= 0x7fffffffffffffff) {
      throw StateError('Invalid encrypted message.');
    }
    final counter = _sent++;
    final aad = [3, ..._counter(counter)];
    final box = await _cipher.encrypt(
      plain,
      secretKey: _sendKey,
      nonce: _nonce(counter),
      aad: aad,
    );
    if (!_closed) {
      _socket.add(
        Uint8List.fromList([
          ..._counter(counter),
          ...box.cipherText,
          ...box.mac.bytes,
        ]),
      );
    }
  }

  Future<dynamic> _decode(dynamic wire) async {
    if (wire is! List<int> || wire.length < 25 || wire.length > 65560) {
      throw const FormatException('Unencrypted or oversized room message.');
    }
    final bytes = Uint8List.fromList(wire);
    final counter = bytes.buffer.asByteData().getUint64(0);
    if (counter != _received) {
      throw const FormatException('Replayed or reordered room message.');
    }
    final plain = await _cipher.decrypt(
      SecretBox(
        bytes.sublist(8, bytes.length - 16),
        nonce: _nonce(counter),
        mac: Mac(bytes.sublist(bytes.length - 16)),
      ),
      secretKey: _receiveKey,
      aad: [3, ..._counter(counter)],
    );
    _received++;
    if (plain.isEmpty || plain[0] > 1) {
      throw const FormatException('Invalid encrypted payload.');
    }
    return plain[0] == 1
        ? utf8.decode(plain.sublist(1))
        : Uint8List.fromList(plain.sublist(1));
  }

  void add(dynamic value) {
    if (_closed) return;
    if (++_queued > 64) {
      unawaited(close());
      return;
    }
    _sending = _sending
        .then((_) => _write(value))
        .catchError((Object _) {
          unawaited(close());
        })
        .whenComplete(() {
          _queued--;
        });
  }

  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
  }) => _events.stream.listen(onData, onError: onError, onDone: onDone);

  Future<void> _receive() async {
    try {
      while (!_closed && await _input.moveNext()) {
        final message = await _decode(_input.current);
        if (!_closed) _events.add(message);
      }
    } catch (_) {
      // Fail closed on tampering; no unauthenticated payload reaches consumers.
    } finally {
      await close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    unawaited(_input.cancel());
    unawaited(_events.close());
    await _socket.close();
  }
}
