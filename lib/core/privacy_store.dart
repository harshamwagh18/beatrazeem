import 'package:flutter/services.dart';

/// Local proof of the notice accepted on this device, without a birth date.
class PrivacyConsent {
  const PrivacyConsent({
    required this.noticeVersion,
    required this.acceptedAt,
    required this.adultConfirmed,
    this.guardianApproval,
  });

  final String noticeVersion;
  final DateTime acceptedAt;
  final bool adultConfirmed;
  final String? guardianApproval;

  /// Guardian receipts require signature/nonce validation by the caller. Merely
  /// finding a token in storage must never grant entry to a child.
  bool accepts(String currentNoticeVersion) =>
      adultConfirmed && noticeVersion == currentNoticeVersion;

  factory PrivacyConsent.fromMap(Map<dynamic, dynamic> values) {
    final version = values['noticeVersion'];
    final time = values['acceptedAtEpochMs'];
    final adult = values['adultConfirmed'];
    final approval = values['guardianApproval'];
    if (version is! String ||
        !_validVersion(version) ||
        time is! int ||
        time <= 0 ||
        time > 8640000000000000 ||
        adult is! bool ||
        (adult
            ? approval != null
            : approval is! String ||
                  approval.trim().isEmpty ||
                  approval.length > 8192)) {
      throw const FormatException('The saved privacy choice is invalid.');
    }
    return PrivacyConsent(
      noticeVersion: version,
      acceptedAt: DateTime.fromMillisecondsSinceEpoch(time, isUtc: true),
      adultConfirmed: adult,
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
    required bool adultConfirmed,
    String? guardianApproval,
  }) async {
    if (!_validVersion(noticeVersion) ||
        (adultConfirmed
            ? guardianApproval != null
            : guardianApproval == null ||
                  guardianApproval.trim().isEmpty ||
                  guardianApproval.length > 8192)) {
      throw const FormatException(
        'Confirm adult eligibility or provide verified guardian approval.',
      );
    }
    await _channel.invokeMethod<void>('saveConsent', {
      'noticeVersion': noticeVersion,
      'adultConfirmed': adultConfirmed,
      'guardianApproval': ?guardianApproval,
    });
  }

  /// Call only after stopping capture, playback and room connections. This also
  /// removes the username; a subsequent start must ask for consent again.
  Future<void> deleteAll() => _channel.invokeMethod<void>('deleteAll');

  Future<String?> readApprovalRequestId() =>
      _channel.invokeMethod<String>('readApprovalRequestId');

  Future<String> getOrCreateApprovalRequestId() async {
    final value = await _channel.invokeMethod<String>(
      'getOrCreateApprovalRequestId',
    );
    if (value == null ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(value)) {
      throw const FormatException('Could not create a valid approval request.');
    }
    return value;
  }

  /// Opens a draft in the user's email app; never sends it automatically.
  Future<bool> composeEmail({
    required String to,
    required String subject,
    required String body,
  }) async =>
      await _channel.invokeMethod<bool>('composeEmail', {
        'to': to,
        'subject': subject,
        'body': body,
      }) ??
      false;
}
