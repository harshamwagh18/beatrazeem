import 'dart:math';
import 'dart:typed_data';

const sampleRate = 48000;
const frameSamples = 960;
const frameBytes = frameSamples * 2;
const frameUs = 20000;
const playoutDelayUs = 200000;

String createRoomCode() =>
    (100000 + Random.secure().nextInt(900000)).toString();
bool validRoomCode(String code) => RegExp(r'^\d{6}$').hasMatch(code);

/// Maps each phone's monotonic clock onto the creator's monotonic timeline.
/// Network delay is filtered; subsequent corrections are slewed so already
/// scheduled audio does not alternate between different clock estimates.
class RoomClock {
  final Stopwatch _watch = Stopwatch()..start();
  int get now => _watch.elapsedMicroseconds;
  int offset = 0;
  int? rtt;
  bool _ready = false;
  int? _lastReceived;
  final List<({int received, int roundTrip, int offset})> _samples = [];
  bool get ready => _ready;

  /// [host] is the creator's receive timestamp. Old peers send just one host
  /// timestamp, so omitted [hostSent] retains the midpoint approximation.
  void sample(int sent, int host, int received, {int? hostSent}) {
    final hostReply = hostSent ?? host;
    final elapsed = received - sent;
    final processing = hostReply - host;
    final roundTrip = elapsed - processing;
    if (elapsed < 0 ||
        processing < 0 ||
        roundTrip < 0 ||
        roundTrip > 250000 ||
        (_lastReceived != null && received <= _lastReceived!)) {
      return;
    }
    _lastReceived = received;
    final measuredOffset = ((host - sent) + (hostReply - received)) ~/ 2;
    _samples.removeWhere((sample) => received - sample.received > 4000000);
    _samples.add((
      received: received,
      roundTrip: roundTrip,
      offset: measuredOffset,
    ));
    if (_samples.length > 16) _samples.removeAt(0);
    final ranked = _samples.toList()
      ..sort((a, b) {
        final delay = a.roundTrip.compareTo(b.roundTrip);
        return delay != 0 ? delay : b.received.compareTo(a.received);
      });
    rtt = ranked.first.roundTrip;
    // Median of three good exchanges avoids pinning the room to one lucky
    // but asymmetric packet. A short sample window follows clock drift.
    final offsets = ranked.take(3).map((sample) => sample.offset).toList()
      ..sort();
    final target = offsets[offsets.length ~/ 2];
    if (!_ready) {
      offset = target;
      _ready = _samples.length >= 3;
    } else {
      offset += ((target - offset) * .25).round().clamp(-1000, 1000);
    }
  }

  void reset() {
    _samples.clear();
    _lastReceived = null;
    _ready = false;
    offset = 0;
    rtt = null;
  }
}

class AudioFrame {
  const AudioFrame(this.sequence, this.playAt, this.pcm, {this.capturedAt});
  final int sequence;
  final int playAt;
  final Uint8List pcm;
  final int? capturedAt;
  int get durationUs => pcm.length * 1000000 ~/ (sampleRate * 2);
  Uint8List encode() {
    final headerSize = capturedAt == null ? 20 : 28;
    final result = Uint8List(headerSize + pcm.length);
    final data = ByteData.sublistView(result);
    data.setUint32(0, capturedAt == null ? 0x42525a31 : 0x42525a32);
    data.setUint32(4, sequence);
    data.setInt64(8, playAt);
    if (capturedAt != null) data.setInt64(16, capturedAt!);
    data.setUint32(headerSize - 4, pcm.length);
    result.setRange(headerSize, result.length, pcm);
    return result;
  }

  static AudioFrame? decode(List<int> bytes) {
    if (bytes.length < 20 || bytes.length > 9600 + 28) return null;
    final raw = Uint8List.fromList(bytes);
    final data = ByteData.sublistView(raw);
    final version = data.getUint32(0);
    if (version != 0x42525a31 && version != 0x42525a32) return null;
    final headerSize = version == 0x42525a32 ? 28 : 20;
    if (raw.length < headerSize) return null;
    final length = data.getUint32(headerSize - 4);
    if ((length != frameBytes && length != 9600) ||
        raw.length != length + headerSize) {
      return null;
    }
    final capturedAt = version == 0x42525a32 ? data.getInt64(16) : null;
    final playAt = data.getInt64(8);
    if (capturedAt != null &&
        (playAt < capturedAt || playAt - capturedAt > 2000000)) {
      return null;
    }
    return AudioFrame(
      data.getUint32(4),
      playAt,
      Uint8List.sublistView(raw, headerSize),
      capturedAt: capturedAt,
    );
  }
}

/// Reframes variable-sized microphone callbacks without losing split samples.
class PcmFramer {
  final List<int> _pending = [];
  Iterable<Uint8List> add(Uint8List bytes) sync* {
    _pending.addAll(bytes);
    while (_pending.length >= frameBytes) {
      yield Uint8List.fromList(_pending.sublist(0, frameBytes));
      _pending.removeRange(0, frameBytes);
    }
  }

  void clear() => _pending.clear();
}
