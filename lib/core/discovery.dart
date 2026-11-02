import 'dart:async';
import 'package:bonsoir/bonsoir.dart';
import 'direct_discovery.dart';
import 'local_network.dart';
import 'protocol.dart';

class RoomDiscovery {
  RoomDiscovery({
    DirectRoomDiscovery? direct,
    this.network = const LocalNetwork(),
    this.useMulticast = true,
    this.searchTimeout = const Duration(seconds: 15),
  }) : direct = direct ?? DirectRoomDiscovery();
  static const type = '_beatrazeem._tcp';
  final DirectRoomDiscovery direct;
  final LocalNetwork network;
  final bool useMulticast;
  final Duration searchTimeout;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription? _events;
  Completer<(String, int)>? _search;

  Future<void> prepareHost() => network.release();

  Future<void> advertise(String code, int port) async {
    // Listen on all interfaces: the hotspot interface is not necessarily the
    // default network, and Android NSD may not advertise on it at all.
    await direct.advertise(code, port);
    if (!useMulticast) return;
    final broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: 'Beatrazeem-$code',
        type: type,
        port: port,
        attributes: {'version': '2'},
      ),
    );
    _broadcast = broadcast;
    unawaited(_advertiseMulticast(broadcast));
  }

  Future<void> _advertiseMulticast(BonsoirBroadcast broadcast) async {
    try {
      await broadcast.initialize();
      if (_broadcast != broadcast) return;
      await broadcast.start();
    } catch (_) {
      // The direct hotspot endpoint is already available when NSD is absent.
      if (_broadcast == broadcast) _broadcast = null;
    } finally {
      if (_broadcast != broadcast) {
        try {
          await broadcast.stop().timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
    }
  }

  Future<(String, int)> find(String code) async {
    if (!validRoomCode(code)) {
      throw const FormatException('Enter exactly 6 digits.');
    }
    final result = Completer<(String, int)>();
    // Cancellation may occur while Android is still resolving the Wi-Fi route.
    unawaited(result.future.then<void>((_) {}, onError: (Object _) {}));
    _search = result;
    var found = false;
    try {
      final gateways = await network.prepareListener();
      if (_search != result) throw StateError('Joining was cancelled.');
      unawaited(
        direct
            .find(code, gateways, timeout: searchTimeout)
            .then((endpoint) {
              if (endpoint != null && !result.isCompleted) {
                result.complete(endpoint);
              }
            })
            .catchError((Object _) {
              /* NSD can still discover shared Wi-Fi rooms. */
            }),
      );
      if (useMulticast) unawaited(_findMulticast(code, result));
      final endpoint = await result.future.timeout(
        searchTimeout,
        onTimeout: () => throw Exception(
          'Room not found. Turn on the creator’s hotspot, connect every listener to it, and check the six-digit code. Keep the creator’s room open.',
        ),
      );
      found = true;
      return endpoint;
    } finally {
      if (_search == result) _search = null;
      direct.cancelSearch();
      await _stopSearch();
      if (!found) await network.release();
    }
  }

  Future<void> _findMulticast(
    String code,
    Completer<(String, int)> result,
  ) async {
    final discovery = BonsoirDiscovery(type: type);
    _discovery = discovery;
    try {
      await discovery.initialize();
      if (_search != result || result.isCompleted) return;
      _events = discovery.eventStream!.listen((event) {
        if (_search != result || result.isCompleted) return;
        if (event is BonsoirDiscoveryServiceFoundEvent &&
            event.service.name == 'Beatrazeem-$code') {
          event.service.resolve(discovery.serviceResolver);
        }
        if (event is BonsoirDiscoveryServiceResolvedEvent &&
            event.service.name == 'Beatrazeem-$code') {
          final ipv4 = event.service.hostAddresses.where(
            (address) => !address.contains(':'),
          );
          if (ipv4.isNotEmpty) {
            result.complete((ipv4.first, event.service.port));
          }
        }
      }, onError: (Object _) {});
      await discovery.start();
    } catch (_) {
      /* Direct hotspot discovery continues independently. */
    } finally {
      if (_search != result || result.isCompleted) {
        try {
          await discovery.stop().timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
    }
  }

  Future<void> _stopSearch() async {
    final events = _events;
    _events = null;
    final discovery = _discovery;
    _discovery = null;
    await events?.cancel();
    try {
      await discovery?.stop().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> stop() async {
    final search = _search;
    _search = null;
    if (search != null && !search.isCompleted) {
      search.completeError(StateError('Joining was cancelled.'));
    }
    await direct.stop();
    await _stopSearch();
    final broadcast = _broadcast;
    _broadcast = null;
    try {
      await broadcast?.stop().timeout(const Duration(seconds: 2));
    } catch (_) {}
    await network.release();
  }
}
