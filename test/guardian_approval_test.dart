import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/core/guardian_approval.dart';
import 'package:beatrazeem/core/privacy_policy.dart';

void main() {
  test(
    'guardian approval binds signature, phone, notice and validity period',
    () async {
      final algorithm = Ed25519();
      final key = await algorithm.newKeyPair();
      final public = base64.encode((await key.extractPublicKey()).bytes);
      final now = DateTime.utc(2026, 11, 2);
      final seconds = now.millisecondsSinceEpoch ~/ 1000;
      const id = 'd4232451-3c52-4639-a3d1-0e38550266a7';
      Future<String> sign(Map<String, dynamic> changes) async {
        final payload = utf8.encode(
          jsonEncode({
            'v': 1,
            'requestId': id,
            'noticeVersion': PrivacyPolicy.noticeVersion,
            'issuedAt': seconds - 60,
            'expiresAt': seconds + 86400,
            ...changes,
          }),
        );
        final signature = await algorithm.sign(payload, keyPair: key);
        return '${base64Url.encode(payload)}.${base64Url.encode(signature.bytes)}';
      }

      Future<DateTime?> check(String token, {String requestId = id}) =>
          GuardianApproval.verify(
            token,
            requestId,
            publicKey: public,
            now: now,
          );
      final valid = await sign({});
      expect(await check(valid), now.add(const Duration(days: 1)));
      expect(await check(valid, requestId: 'another-phone'), isNull);
      for (final changes in <Map<String, dynamic>>[
        {'noticeVersion': 'old'},
        {'issuedAt': seconds + 1},
        {'expiresAt': seconds},
        {'expiresAt': seconds + 91 * 86400},
        {'v': 2},
        {'issuedAt': 'invalid'},
      ]) {
        expect(await check(await sign(changes)), isNull);
      }
      final parts = valid.split('.');
      final payload = base64Url.decode(parts[0]);
      payload[0] ^= 1;
      expect(await check('${base64Url.encode(payload)}.${parts[1]}'), isNull);
      expect(
        await GuardianApproval.verify(
          valid,
          id,
          publicKey: PrivacyPolicy.guardianPublicKey,
          now: now,
        ),
        isNull,
      );
      expect(await check('bad.token'), isNull);
      expect(await check('x' * 5000), isNull);
    },
  );
}
