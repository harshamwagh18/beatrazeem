import 'package:flutter/services.dart';

/// Local notice receipt. The age declaration is not age or identity verification.
class PrivacyConsent {
  const PrivacyConsent({
    required this.noticeVersion,
    required this.acceptedAt,
    this.minimumAgeConfirmed = false,
    this.adultConfirmed = false,
    this.guardianApproval,
  });

  final String noticeVersion;
  final DateTime acceptedAt;
  final bool minimumAgeConfirmed;

  /// Retained only to read older receipts without turning them into a new choice.
  final bool adultConfirmed;
  final String? guardianApproval;

  bool accepts(String currentNoticeVersion) =>
      minimumAgeConfirmed &&
      !adultConfirmed &&
      guardianApproval == null &&
      noticeVersion == currentNoticeVersion;

  factory PrivacyConsent.fromMap(Map<dynamic, dynamic> values) {
    final version = values['noticeVersion'];
    final time = values['acceptedAtEpochMs'];
    final minimumAge = values['minimumAgeConfirmed'];
    final adult = values['adultConfirmed'];
    final approval = values['guardianApproval'];
    final currentSchema = values.containsKey('minimumAgeConfirmed');
    final validChoice = currentSchema
        ? minimumAge == true &&
              (adult == null || adult == false) &&
              approval == null
        : adult is bool &&
              (adult
                  ? approval == null
                  : approval is String &&
                        approval.trim().isNotEmpty &&
                        approval.length <= 8192);
    if (version is! String ||
        !_validVersion(version) ||
        time is! int ||
        time <= 0 ||
        time > 8640000000000000 ||
        !validChoice) {
      throw const FormatException('The saved privacy choice is invalid.');
    }
    return PrivacyConsent(
      noticeVersion: version,
      acceptedAt: DateTime.fromMillisecondsSinceEpoch(time, isUtc: true),
      minimumAgeConfirmed: currentSchema,
      adultConfirmed: adult == true,
      guardianApproval: approval as String?,
    );
  }
}

bool _validVersion(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$').hasMatch(value);

/// Privacy records share the profile's private preference file, so withdrawal
/// can erase both atomically. Storage errors propagate to prevent false success.
class PrivacyStore {
  const PrivacyStore();
  static const _channel = MethodChannel('beatrazeem/privacy');

  Future<PrivacyConsent?> readConsent() async {
    final value = await _channel.invokeMapMethod<dynamic, dynamic>(
      'readConsent',
    );
    return value == null ? null : PrivacyConsent.fromMap(value);
  }

  Future<void> saveConsent({
    required String noticeVersion,
    required bool minimumAgeConfirmed,
  }) async {
    if (!_validVersion(noticeVersion) || !minimumAgeConfirmed) {
      throw const FormatException('Confirm that you are 9 or older.');
    }
    await _channel.invokeMethod<void>('saveConsent', {
      'noticeVersion': noticeVersion,
      'minimumAgeConfirmed': minimumAgeConfirmed,
    });
  }

  /// Call only after stopping capture, playback and room connections. This also
  /// removes the username and any legacy guardian data; consent is needed again.
  Future<void> deleteAll() => _channel.invokeMethod<void>('deleteAll');
}
