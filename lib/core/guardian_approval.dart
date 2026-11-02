import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'privacy_policy.dart';

class GuardianApproval {
  static Future<DateTime?> verify(
    String token,
    String requestId, {
    String publicKey = PrivacyPolicy.guardianPublicKey,
    DateTime? now,
  }) async {
    try {
      if (token.length > 4096 || requestId.isEmpty) return null;
      final parts = token.split('.');
      if (parts.length != 2) return null;
      final payload = base64Url.decode(base64Url.normalize(parts[0]));
      final signature = base64Url.decode(base64Url.normalize(parts[1]));
      final key = base64.decode(publicKey);
      if (key.length != 32 || signature.length != 64) return null;
      if (!await Ed25519().verify(
        payload,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
        ),
      )) {
        return null;
      }
      final data = jsonDecode(utf8.decode(payload));
      if (data is! Map ||
          data['v'] != 1 ||
          data['requestId'] != requestId ||
          data['noticeVersion'] != PrivacyPolicy.noticeVersion ||
          data['issuedAt'] is! int ||
          data['expiresAt'] is! int) {
        return null;
      }
      final issued = data['issuedAt'] as int;
      final expires = data['expiresAt'] as int;
      final seconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
      if (issued > seconds ||
          issued <= 0 ||
          expires <= seconds ||
          expires <= issued ||
          expires - issued > 90 * 86400) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true);
    } catch (_) {
      return null;
    }
  }
}
