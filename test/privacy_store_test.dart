import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/core/privacy_store.dart';
import 'package:beatrazeem/core/profile_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('beatrazeem/privacy');
  const profileChannel = MethodChannel('beatrazeem/profile');
  const store = PrivacyStore();
  const current = '2026-11-04.1';
  final valid = <String, Object>{
    'noticeVersion': current,
    'acceptedAtEpochMs': 1793664000000,
    'noticeAccepted': true,
  };
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

  test('new consent applies only to the notice actually accepted', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => valid);
    final consent = (await store.readConsent())!;
    expect(consent.accepts(current), isTrue);
    expect(consent.accepts('2026-11-05.1'), isFalse);
    expect(consent.acceptedAt.isUtc, isTrue);
    expect(consent.noticeAccepted, isTrue);
    expect(consent.adultConfirmed, isFalse);
    expect(consent.guardianApproval, isNull);
  });

  test('corrupt or incomplete current receipts fail closed', () async {
    for (final receipt in [
      {...valid, 'noticeVersion': ''},
      {...valid, 'acceptedAtEpochMs': -1},
      {...valid, 'acceptedAtEpochMs': 8640000000000001},
      {...valid, 'acceptedAtEpochMs': 'yesterday'},
      {...valid, 'noticeAccepted': false},
      {...valid, 'noticeAccepted': 'true'},
      {...valid, 'noticeAccepted': null},
      {'noticeVersion': current},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => receipt);
      await expectLater(store.readConsent(), throwsFormatException);
    }
  });

  test('new notice receipt cannot mix age or guardian claims', () async {
    for (final receipt in [
      {...valid, 'minimumAgeConfirmed': true},
      {...valid, 'minimumAgeConfirmed': 'false'},
      {...valid, 'adultConfirmed': true},
      {...valid, 'adultConfirmed': 'false'},
      {...valid, 'guardianApproval': 'legacy-token'},
      {...valid, 'guardianApproval': ''},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => receipt);
      await expectLater(store.readConsent(), throwsFormatException);
    }
  });

  test('legacy adult receipt remains readable but needs a new choice', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'noticeVersion': current,
        'acceptedAtEpochMs': 1793577600000,
        'adultConfirmed': true,
      },
    );
    final receipt = (await store.readConsent())!;
    expect(receipt.adultConfirmed, isTrue);
    expect(receipt.noticeAccepted, isFalse);
    // Even a matching notice string cannot turn old-schema storage into consent.
    expect(receipt.accepts(current), isFalse);
  });

  test(
    'legacy guardian receipt remains readable without granting entry',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'noticeVersion': current,
          'acceptedAtEpochMs': 1793577600000,
          'adultConfirmed': false,
          'guardianApproval': 'old-signed-token',
        },
      );
      final receipt = (await store.readConsent())!;
      expect(receipt.guardianApproval, 'old-signed-token');
      expect(receipt.noticeAccepted, isFalse);
      expect(receipt.accepts(current), isFalse);
    },
  );

  test(
    'legacy age declaration remains readable without accepting new terms',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'noticeVersion': '2026-11-03.1',
          'acceptedAtEpochMs': 1793664000000,
          'minimumAgeConfirmed': true,
        },
      );
      final receipt = (await store.readConsent())!;
      expect(receipt.minimumAgeConfirmed, isTrue);
      expect(receipt.noticeAccepted, isFalse);
      expect(receipt.accepts(current), isFalse);
    },
  );

  test('corrupt legacy receipts still fail closed', () async {
    final old = {
      'noticeVersion': '2026-11-02.1',
      'acceptedAtEpochMs': 1793577600000,
    };
    for (final receipt in [
      {...old, 'adultConfirmed': false},
      {...old, 'adultConfirmed': 'true'},
      {...old, 'adultConfirmed': false, 'guardianApproval': '   '},
      {...old, 'adultConfirmed': true, 'guardianApproval': 'token'},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => receipt);
      await expectLater(store.readConsent(), throwsFormatException);
    }
  });

  test(
    'only the Continue acknowledgement reaches storage without age or adult claims',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      await expectLater(
        store.saveConsent(noticeVersion: current, noticeAccepted: false),
        throwsFormatException,
      );
      await expectLater(
        store.saveConsent(noticeVersion: '', noticeAccepted: true),
        throwsFormatException,
      );
      expect(calls, isEmpty);
      await store.saveConsent(noticeVersion: current, noticeAccepted: true);
      expect(calls.single.method, 'saveConsent');
      expect(calls.single.arguments, {
        'noticeVersion': current,
        'noticeAccepted': true,
      });
    },
  );

  test('storage failures propagate for reads, consent and erasure', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'privacy', message: 'Storage unavailable');
    });
    await expectLater(store.readConsent(), throwsA(isA<PlatformException>()));
    await expectLater(
      store.saveConsent(noticeVersion: current, noticeAccepted: true),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(store.deleteAll(), throwsA(isA<PlatformException>()));
  });

  test('legacy constructor defaults cannot grant current eligibility', () {
    for (final receipt in [
      PrivacyConsent(noticeVersion: current, acceptedAt: DateTime.utc(2026)),
      PrivacyConsent(
        noticeVersion: current,
        acceptedAt: DateTime.utc(2026),
        adultConfirmed: true,
      ),
      PrivacyConsent(
        noticeVersion: current,
        acceptedAt: DateTime.utc(2026),
        guardianApproval: 'token',
      ),
      PrivacyConsent(
        noticeVersion: current,
        acceptedAt: DateTime.utc(2026),
        noticeAccepted: true,
        adultConfirmed: true,
      ),
    ]) {
      expect(receipt.accepts(current), isFalse);
    }
  });

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
