import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/core/privacy_policy.dart';
import 'package:beatrazeem/core/privacy_store.dart';
import 'package:beatrazeem/main.dart';
import 'package:beatrazeem/ui/privacy_screen.dart';
import 'host_microphone_test.dart'
    show TestProfileStore, TestRoom, TestAudio, TestDiscovery;

class _PrivacyTestStore extends PrivacyStore {
  _PrivacyTestStore({this.profile, bool accepted = false}) {
    if (accepted) receipt = adultReceipt;
  }
  static PrivacyConsent get adultReceipt => PrivacyConsent(
    noticeVersion: PrivacyPolicy.noticeVersion,
    acceptedAt: DateTime.utc(2026, 11, 2),
    adultConfirmed: true,
  );
  final TestProfileStore? profile;
  PrivacyConsent? receipt;
  bool failSave = false, failDelete = false, emailAvailable = false;
  int saves = 0, deletes = 0;
  String? emailTo, emailSubject, emailBody;
  @override
  Future<PrivacyConsent?> readConsent() async => receipt;
  @override
  Future<void> saveConsent({
    required String noticeVersion,
    required bool adultConfirmed,
    String? guardianApproval,
  }) async {
    if (failSave) throw StateError('Privacy save failed');
    saves++;
    receipt = PrivacyConsent(
      noticeVersion: noticeVersion,
      acceptedAt: DateTime.now().toUtc(),
      adultConfirmed: adultConfirmed,
      guardianApproval: guardianApproval,
    );
  }

  @override
  Future<void> deleteAll() async {
    if (failDelete) throw StateError('Privacy deletion failed; please retry');
    deletes++;
    receipt = null;
    profile?.name = null;
  }

  @override
  Future<String?> readApprovalRequestId() async =>
      'e620bc6d-fc61-4a7f-b708-796de85077fb';
  @override
  Future<String> getOrCreateApprovalRequestId() async =>
      (await readApprovalRequestId())!;
  @override
  Future<bool> composeEmail({
    required String to,
    required String subject,
    required String body,
  }) async {
    emailTo = to;
    emailSubject = subject;
    emailBody = body;
    return emailAvailable;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const adultChoice = 'I am 18 or older and can give consent for myself.';
  const adultAgreement =
      'I agree to the personal-data uses described in this notice.';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String? clipboard;
  setUp(() {
    clipboard = null;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      null,
    );
  });

  Future<void> setup(WidgetTester tester, Widget widget) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Widget screen(
    _PrivacyTestStore store, {
    Future<void> Function()? accepted,
    bool gate = true,
  }) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PrivacyScreen(
          store: store,
          requiredBeforeUse: gate,
          onAccepted: accepted ?? () async {},
          onWithdraw: store.deleteAll,
        ),
      ),
    ),
  );
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets(
    'adult consent starts unchecked and needs both affirmative choices',
    (tester) async {
      final store = _PrivacyTestStore();
      var accepted = false;
      await setup(
        tester,
        screen(
          store,
          accepted: () async {
            accepted = true;
          },
        ),
      );
      FilledButton button() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Accept and continue'),
      );
      expect(button().onPressed, isNull);
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((item) => item.value == false),
        isTrue,
      );
      await tap(tester, adultChoice);
      expect(button().onPressed, isNull);
      await tap(tester, adultAgreement);
      expect(button().onPressed, isNotNull);
      await tap(tester, 'Accept and continue');
      expect(store.saves, 1);
      expect(accepted, isTrue);
      expect(store.receipt!.noticeVersion, PrivacyPolicy.noticeVersion);
      await close(tester);
    },
  );

  testWidgets('a saved username alone cannot bypass the notice gate', (
    tester,
  ) async {
    final profile = TestProfileStore()..name = 'Existing name';
    final store = _PrivacyTestStore(profile: profile);
    final room = TestRoom();
    await setup(
      tester,
      BeatrazeemApp(
        studio: Studio(
          profileStore: profile,
          privacyStore: store,
          room: room,
          audio: TestAudio(),
          discovery: TestDiscovery(),
        ),
      ),
    );
    expect(find.text('Accept and continue'), findsOneWidget);
    expect(find.text('Create a room'), findsNothing);
    expect(room.connected, isFalse);
    await tap(tester, adultChoice);
    await tap(tester, adultAgreement);
    await tap(tester, 'Accept and continue');
    expect(find.text('Hey, Existing name.'), findsOneWidget);
    expect(store.saves, 1);
    await close(tester);
  });

  testWidgets('stored child receipt is reverified before room access', (
    tester,
  ) async {
    final profile = TestProfileStore()..name = 'Existing name';
    final store = _PrivacyTestStore(profile: profile)
      ..receipt = PrivacyConsent(
        noticeVersion: PrivacyPolicy.noticeVersion,
        acceptedAt: DateTime.utc(2026, 11, 2),
        adultConfirmed: false,
        guardianApproval: 'invalid-stored-token',
      );
    final room = TestRoom();
    await setup(
      tester,
      BeatrazeemApp(
        studio: Studio(
          profileStore: profile,
          privacyStore: store,
          room: room,
          audio: TestAudio(),
          discovery: TestDiscovery(),
        ),
      ),
    );
    expect(find.text('Accept and continue'), findsOneWidget);
    expect(find.text('Create a room'), findsNothing);
    expect(room.connected, isFalse);
    expect(store.saves, 0);
    await close(tester);
  });

  testWidgets('invalid guardian approval cannot save consent or enter', (
    tester,
  ) async {
    final store = _PrivacyTestStore();
    var accepted = false;
    await setup(
      tester,
      screen(
        store,
        accepted: () async {
          accepted = true;
        },
      ),
    );
    await tap(tester, 'Parent or lawful guardian approval');
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'not-a-signed-approval');
    await tap(
      tester,
      'The verified guardian approved this notice and this phone’s use.',
    );
    await tap(tester, 'Accept and continue');
    expect(find.textContaining('Approval is invalid'), findsOneWidget);
    expect(store.saves, 0);
    expect(accepted, isFalse);
    await close(tester);
  });

  testWidgets('a failed consent save never grants entry', (tester) async {
    final store = _PrivacyTestStore()..failSave = true;
    var accepted = false;
    await setup(
      tester,
      screen(
        store,
        accepted: () async {
          accepted = true;
        },
      ),
    );
    await tap(tester, adultChoice);
    await tap(tester, adultAgreement);
    await tap(tester, 'Accept and continue');
    expect(find.textContaining('Privacy save failed'), findsOneWidget);
    expect(accepted, isFalse);
    expect(store.receipt, isNull);
    await close(tester);
  });

  for (final failDelete in [false, true]) {
    testWidgets(
      'withdrawal stops the active room and microphone${failDelete ? ' even when erasure fails' : ' and erases local identity'}',
      (tester) async {
        final profile = TestProfileStore()..name = 'Razeem';
        final store = _PrivacyTestStore(profile: profile, accepted: true)
          ..failDelete = failDelete;
        final room = TestRoom();
        await room.create('123456', username: 'Razeem', name: 'My room');
        final audio = TestAudio()..microphone = true;
        await setup(
          tester,
          BeatrazeemApp(
            studio: Studio(
              profileStore: profile,
              privacyStore: store,
              room: room,
              audio: audio,
              discovery: TestDiscovery(),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Privacy & your data'));
        await tester.pumpAndSettle();
        await tap(tester, 'Withdraw consent & delete local data');
        await tap(tester, 'Withdraw and delete');
        expect(room.connected, isFalse);
        expect(audio.microphone, isFalse);
        expect(audio.outputStops, greaterThan(0));
        if (failDelete) {
          expect(
            find.textContaining('Local data could not be deleted'),
            findsOneWidget,
          );
          expect(store.deletes, 0);
          expect(profile.name, 'Razeem');
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.text('Accept and continue'), findsOneWidget);
          expect(find.text('Create a room'), findsNothing);
        } else {
          expect(store.deletes, 1);
          expect(store.receipt, isNull);
          expect(profile.name, isNull);
          expect(find.text('Accept and continue'), findsOneWidget);
        }
        await close(tester);
      },
    );
  }

  testWidgets(
    'missing email app offers a copyable request without submitting it',
    (tester) async {
      final store = _PrivacyTestStore();
      await setup(tester, screen(store, gate: false));
      await tap(tester, 'Open email request');
      expect(store.emailTo, PrivacyPolicy.contactEmail);
      expect(store.emailSubject, contains('Access to my data'));
      expect(find.textContaining('No email app is available'), findsOneWidget);
      await tap(tester, 'Copy request');
      expect(clipboard, contains('To: ${PrivacyPolicy.contactEmail}'));
      expect(clipboard, contains('Access to my data'));
      expect(store.saves, 0);
      await close(tester);
    },
  );
  testWidgets('guardian email fallback includes the phone approval reference', (
    tester,
  ) async {
    final store = _PrivacyTestStore();
    await setup(tester, screen(store));
    await tap(tester, 'Parent or lawful guardian approval');
    await tap(tester, 'Request guardian verification');
    await tap(tester, 'Copy request');
    expect(clipboard, contains('Beatrazeem guardian approval request'));
    expect(clipboard, contains(await store.readApprovalRequestId()));
    expect(clipboard, contains(PrivacyPolicy.noticeVersion));
    expect(store.saves, 0);
    await close(tester);
  });
}
