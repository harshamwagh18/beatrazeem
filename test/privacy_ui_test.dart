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
    if (accepted) receipt = acceptedReceipt;
  }
  static PrivacyConsent get acceptedReceipt => PrivacyConsent(
    noticeVersion: PrivacyPolicy.noticeVersion,
    acceptedAt: DateTime.utc(2026, 11, 2),
    noticeAccepted: true,
  );
  final TestProfileStore? profile;
  PrivacyConsent? receipt;
  bool failSave = false, failDelete = false;
  int saves = 0, deletes = 0;
  @override
  Future<PrivacyConsent?> readConsent() async => receipt;
  @override
  Future<void> saveConsent({
    required String noticeVersion,
    required bool noticeAccepted,
  }) async {
    if (failSave) throw StateError('Privacy save failed');
    saves++;
    receipt = PrivacyConsent(
      noticeVersion: noticeVersion,
      acceptedAt: DateTime.now().toUtc(),
      noticeAccepted: noticeAccepted,
    );
  }

  @override
  Future<void> deleteAll() async {
    if (failDelete) throw StateError('Privacy deletion failed; please retry');
    deletes++;
    receipt = null;
    profile?.name = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const agreement =
      'By continuing, I agree to the terms and conditions and privacy notice.';
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
    'plain agreement waits for Continue and saves no age declaration',
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
        find.widgetWithText(FilledButton, 'Continue'),
      );
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('I am 9 years old or older.'), findsNothing);
      expect(find.text(agreement), findsOneWidget);
      expect(store.saves, 0);
      expect(accepted, isFalse);
      expect(button().onPressed, isNotNull);
      await tap(tester, 'Continue');
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
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Create a room'), findsNothing);
    expect(room.connected, isFalse);
    await tap(tester, 'Continue');
    expect(find.text('Hey, Existing name.'), findsOneWidget);
    expect(store.saves, 1);
    await close(tester);
  });

  for (final legacy in ['adult', 'guardian', 'age']) {
    testWidgets(
      'earlier $legacy receipt requires Continue for the updated notice',
      (tester) async {
        final profile = TestProfileStore()..name = 'Existing name';
        final store = _PrivacyTestStore(profile: profile)
          ..receipt = PrivacyConsent(
            noticeVersion: legacy == 'age' ? '2026-11-03.1' : '2026-11-02.1',
            acceptedAt: DateTime.utc(2026, 11, 2),
            adultConfirmed: legacy == 'adult',
            minimumAgeConfirmed: legacy == 'age',
            guardianApproval: legacy == 'guardian' ? 'old-signed-token' : null,
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
        expect(find.text('Continue'), findsOneWidget);
        expect(find.text('Create a room'), findsNothing);
        expect(room.connected, isFalse);
        expect(store.saves, 0);
        await tap(tester, 'Continue');
        expect(find.text('Hey, Existing name.'), findsOneWidget);
        expect(profile.name, 'Existing name');
        expect(store.receipt!.noticeAccepted, isTrue);
        expect(store.receipt!.minimumAgeConfirmed, isFalse);
        expect(store.receipt!.adultConfirmed, isFalse);
        expect(store.receipt!.guardianApproval, isNull);
        await close(tester);
      },
    );
  }

  testWidgets(
    'current notice receipt opens saved profile without asking again',
    (tester) async {
      final profile = TestProfileStore()..name = 'Razeem';
      final store = _PrivacyTestStore(profile: profile, accepted: true);
      await setup(
        tester,
        BeatrazeemApp(
          studio: Studio(
            profileStore: profile,
            privacyStore: store,
            room: TestRoom(),
            audio: TestAudio(),
            discovery: TestDiscovery(),
          ),
        ),
      );
      expect(find.text('Hey, Razeem.'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
      expect(store.saves, 0);
      await close(tester);
    },
  );

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
    await tap(tester, 'Continue');
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
          expect(find.text('Continue'), findsOneWidget);
          expect(find.text('Create a room'), findsNothing);
        } else {
          expect(store.deletes, 1);
          expect(store.receipt, isNull);
          expect(profile.name, isNull);
          expect(find.text('Continue'), findsOneWidget);
        }
        await close(tester);
      },
    );
  }

  for (final gate in [true, false]) {
    testWidgets(
      'privacy ${gate ? 'onboarding hides' : 'centre retains'} the data and contact footer',
      (tester) async {
        final store = _PrivacyTestStore();
        await setup(tester, screen(store, gate: gate));
        expect(find.text('Parent or lawful guardian approval'), findsNothing);
        expect(find.text('Request guardian verification'), findsNothing);
        expect(find.text('Privacy requests & complaints'), findsNothing);
        expect(find.text('Open email request'), findsNothing);
        expect(find.text('Copy request'), findsNothing);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        if (gate) {
          expect(find.text('Data on this phone'), findsNothing);
          expect(find.text('Copy my data summary'), findsNothing);
          expect(find.byKey(const ValueKey('privacy-contact')), findsNothing);
          expect(
            find.text('Withdraw consent & delete local data'),
            findsNothing,
          );
          expect(find.text('Continue'), findsOneWidget);
          expect(find.byKey(const ValueKey('terms-statement')), findsOneWidget);
        } else {
          final contact = tester.widget<SelectableText>(
            find.byKey(const ValueKey('privacy-contact')),
          );
          expect(
            contact.data,
            'If you have any queries, contact gamelauncer223@gmail.com.',
          );
          expect(
            find.text('Withdraw consent & delete local data'),
            findsOneWidget,
          );
          await tap(tester, 'Data on this phone');
          await tap(tester, 'Copy my data summary');
          expect(clipboard, contains('Beatrazeem local data'));
        }
        expect(store.saves, 0);
        await close(tester);
      },
    );
  }
}
