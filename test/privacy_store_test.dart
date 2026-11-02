import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/core/privacy_store.dart';
import 'package:beatrazeem/core/profile_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('beatrazeem/privacy');
  const profileChannel = MethodChannel('beatrazeem/profile');
  const store = PrivacyStore();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(profileChannel, null);
  });

  test('legacy profile without consent cannot pass the privacy gate', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await store.readConsent(), isNull);
  });

  test(
    'consent applies only to the notice version actually accepted',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'noticeVersion': '2026-11-02.1',
          'acceptedAtEpochMs': 1793577600000,
          'adultConfirmed': true,
        },
      );
      final consent = (await store.readConsent())!;
      expect(consent.accepts('2026-11-02.1'), isTrue);
      expect(consent.accepts('2026-11-03.1'), isFalse);
      expect(consent.acceptedAt.isUtc, isTrue);
    },
  );

  test('corrupt or incomplete receipts fail closed', () async {
    final valid = <String, Object>{
      'noticeVersion': 'v1',
      'acceptedAtEpochMs': 1793577600000,
      'adultConfirmed': true,
    };
    for (final receipt in [
      {...valid, 'noticeVersion': ''},
      {...valid, 'acceptedAtEpochMs': -1},
      {...valid, 'acceptedAtEpochMs': 'yesterday'},
      {...valid, 'adultConfirmed': false},
      {'noticeVersion': 'v1'},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => receipt);
      await expectLater(store.readConsent(), throwsFormatException);
    }
  });

  test(
    'only an affirmative adult choice reaches storage; no birth date is sent',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      await expectLater(
        store.saveConsent(noticeVersion: 'v1', adultConfirmed: false),
        throwsFormatException,
      );
      await expectLater(
        store.saveConsent(noticeVersion: '', adultConfirmed: true),
        throwsFormatException,
      );
      expect(calls, isEmpty);
      await store.saveConsent(noticeVersion: 'v1', adultConfirmed: true);
      expect(calls.single.method, 'saveConsent');
      expect(calls.single.arguments, {
        'noticeVersion': 'v1',
        'adultConfirmed': true,
      });
    },
  );

  test('storage failures propagate for reads, consent and erasure', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'privacy', message: 'Storage unavailable');
    });
    await expectLater(store.readConsent(), throwsA(isA<PlatformException>()));
    await expectLater(
      store.saveConsent(noticeVersion: 'v1', adultConfirmed: true),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(store.deleteAll(), throwsA(isA<PlatformException>()));
  });

  test(
    'stored guardian approval never grants entry without signature validation',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'noticeVersion': 'v1',
          'acceptedAtEpochMs': 1793577600000,
          'adultConfirmed': false,
          'guardianApproval': 'unverified-stored-token',
        },
      );
      final receipt = (await store.readConsent())!;
      expect(receipt.guardianApproval, 'unverified-stored-token');
      expect(receipt.accepts('v1'), isFalse);
    },
  );

  test('adult and guardian consent alternatives cannot be mixed', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(
      store.saveConsent(
        noticeVersion: 'v1',
        adultConfirmed: true,
        guardianApproval: 'token',
      ),
      throwsFormatException,
    );
    await expectLater(
      store.saveConsent(
        noticeVersion: 'v1',
        adultConfirmed: false,
        guardianApproval: '  ',
      ),
      throwsFormatException,
    );
  });

  test('guardian token reaches storage only through explicit save', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'saveConsent');
      expect(call.arguments, {
        'noticeVersion': 'v1',
        'adultConfirmed': false,
        'guardianApproval': 'signed-token',
      });
      return null;
    });
    await store.saveConsent(
      noticeVersion: 'v1',
      adultConfirmed: false,
      guardianApproval: 'signed-token',
    );
  });

  test(
    'approval nonce read does not create one and create validates native output',
    () async {
      var created = false;
      const requestId = 'e620bc6d-fc61-4a7f-b708-796de85077fb';
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'readApprovalRequestId') {
          return created ? requestId : null;
        }
        expect(call.method, 'getOrCreateApprovalRequestId');
        created = true;
        return requestId;
      });
      expect(await store.readApprovalRequestId(), isNull);
      expect(created, isFalse);
      expect(await store.getOrCreateApprovalRequestId(), requestId);
      expect(await store.readApprovalRequestId(), requestId);
      messenger.setMockMethodCallHandler(channel, (_) async => 'invalid-id');
      await expectLater(
        store.getOrCreateApprovalRequestId(),
        throwsFormatException,
      );
    },
  );

  test(
    'email opens an explicit draft and reports missing email apps',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'composeEmail');
        expect(call.arguments, {
          'to': 'privacy@example.org',
          'subject': 'My request',
          'body': 'Please help.',
        });
        return true;
      });
      expect(
        await store.composeEmail(
          to: 'privacy@example.org',
          subject: 'My request',
          body: 'Please help.',
        ),
        isTrue,
      );
      messenger.setMockMethodCallHandler(channel, (_) async => false);
      expect(
        await store.composeEmail(
          to: 'privacy@example.org',
          subject: 'My request',
          body: 'Please help.',
        ),
        isFalse,
      );
    },
  );

  test('withdrawal requests one atomic erase of profile and consent', () async {
    var cleared = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'deleteAll');
      expect(call.arguments, isNull);
      cleared = true;
      return null;
    });
    await store.deleteAll();
    expect(cleared, isTrue);
  });

  test(
    'username can be removed without replacing it with another name',
    () async {
      messenger.setMockMethodCallHandler(profileChannel, (call) async {
        expect(call.method, 'deleteUsername');
        expect(call.arguments, isNull);
        return null;
      });
      await const ProfileStore().deleteUsername();
    },
  );
}
