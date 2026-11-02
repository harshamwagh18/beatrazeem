import 'dart:io';
import 'package:flutter/services.dart';

class LocalNetwork {
  const LocalNetwork();
  static const _channel = MethodChannel('beatrazeem/network');

  Future<List<String>> prepareListener() async {
    if (!Platform.isAndroid) return const [];
    final addresses = await _channel.invokeListMethod<String>(
      'prepareListener',
    );
    return addresses ?? const [];
  }

  Future<void> release() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('release');
  }
}
