import 'package:flutter/services.dart';
import 'room_member.dart';

/// The Android bridge stores the name in this app's private preferences.
class ProfileStore {
  const ProfileStore();
  static const _channel = MethodChannel('beatrazeem/profile');

  Future<String?> readUsername() async {
    final value = await _channel.invokeMethod<String>('readUsername');
    if (value == null) return null;
    try {
      return roomText(value, limit: 24, label: 'Username');
    } on FormatException {
      // Invalid old data should never prevent someone choosing a valid name.
      return null;
    }
  }

  Future<void> saveUsername(String value) async {
    final name = roomText(value, limit: 24, label: 'Username');
    await _channel.invokeMethod<void>('saveUsername', name);
  }
}
