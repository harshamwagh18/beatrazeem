import 'package:flutter/services.dart';

/// Local record of the notice accepted by pressing Continue.
class PrivacyConsent {
  const PrivacyConsent({
    required this.noticeVersion,
    required this.acceptedAt,
    this.noticeAccepted = false,
    this.minimumAgeConfirmed = false,
    this.adultConfirmed = false,
    this.guardianApproval,
  });

  final String noticeVersion;
  final DateTime acceptedAt;
  final bool noticeAccepted;
  final bool minimumAgeConfirmed;

  /// Retained only to read older receipts without turning them into a new choice.
  final bool adultConfirmed;
  final String? guardianApproval;

  bool accepts(String currentNoticeVersion) =>
      noticeAccepted &&
      !minimumAgeConfirmed &&
      !adultConfirmed &&
      guardianApproval == null &&
      noticeVersion == currentNoticeVersion;

  factory PrivacyConsent.fromMap(Map<dynamic, dynamic> values) {
    final version = values['noticeVersion'];
    final time = values['acceptedAtEpochMs'];
    final accepted = values['noticeAccepted'];
    final minimumAge = values['minimumAgeConfirmed'];
    final adult = values['adultConfirmed'];
    final approval = values['guardianApproval'];
    final currentSchema = values.containsKey('noticeAccepted');
    final ageSchema = values.containsKey('minimumAgeConfirmed');
    final validChoice = currentSchema
        ? accepted == true &&
              (minimumAge == null || minimumAge == false) &&
              (adult == null || adult == false) &&
              approval == null
        : ageSchema
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
      noticeAccepted: currentSchema,
      minimumAgeConfirmed: minimumAge == true,
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
    required bool noticeAccepted,
  }) async {
    if (!_validVersion(noticeVersion) || !noticeAccepted) {
      throw const FormatException('Continue to accept the current notice.');
    }
    await _channel.invokeMethod<void>('saveConsent', {
      'noticeVersion': noticeVersion,
      'noticeAccepted': noticeAccepted,
    });
  }

  /// Call only after stopping capture, playback and room connections. This also
  /// removes the username and any legacy guardian data; consent is needed again.
  Future<void> deleteAll() => _channel.invokeMethod<void>('deleteAll');
}
