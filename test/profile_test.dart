import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/core/profile_store.dart';
import 'package:beatrazeem/main.dart';
import 'host_microphone_test.dart'
    show TestRoom, TestAudio, TestDiscovery, TestProfileStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('beatrazeem/profile');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (_) async => null,
    );
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> openApp(
    WidgetTester tester,
    ProfileStore store, {
    TestRoom? room,
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      BeatrazeemApp(
        studio: Studio(
          profileStore: store,
          room: room ?? TestRoom(),
          audio: TestAudio(),
          discovery: TestDiscovery(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets(
    'name survives a fresh app and profile edits; cancel keeps saved name',
    (tester) async {
      // Exercise the actual storage bridge across new store and widget instances.
      String? diskName;
      var writes = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'readUsername') return diskName;
        expect(call.method, 'saveUsername');
        diskName = call.arguments as String;
        writes++;
        return null;
      });
      await openApp(tester, const ProfileStore());
      await tester.enterText(
        find.byKey(const ValueKey('username')),
        '  Razeem  ',
      );
      await tap(tester, 'Let’s go');
      expect(diskName, 'Razeem');
      expect(find.text('Hey, Razeem.'), findsOneWidget);
      await closeApp(tester);

      final room = TestRoom();
      await openApp(tester, const ProfileStore(), room: room);
      expect(find.byKey(const ValueKey('username')), findsNothing);
      expect(find.text('Hey, Razeem.'), findsOneWidget);
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('profile-username')),
            )
            .controller!
            .text,
        'Razeem',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-username')),
        'Cancelled name',
      );
      await tap(tester, 'Cancel');
      expect(diskName, 'Razeem');
      expect(writes, 1);

      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-username')),
        ' ',
      );
      await tap(tester, 'Save changes');
      expect(
        find.text('Username must be between 1 and 24 characters.'),
        findsOneWidget,
      );
      expect(writes, 1);
      await tester.enterText(
        find.byKey(const ValueKey('profile-username')),
        'Zoë 🎵',
      );
      await tap(tester, 'Save changes');
      expect(diskName, 'Zoë 🎵');
      expect(find.text('Hey, Zoë 🎵.'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('room-name')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const ValueKey('room-name')),
        'Music room',
      );
      await tap(tester, 'Create a room');
      expect(room.members.single.name, 'Zoë 🎵');
      final roomCode = room.code;
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-username')),
        'New name',
      );
      await tap(tester, 'Save changes');
      expect(room.connected, isTrue);
      expect(room.code, roomCode);
      expect(room.members.single.name, 'New name');
      await closeApp(tester);
      await openApp(tester, const ProfileStore());
      expect(find.text('Hey, New name.'), findsOneWidget);
      expect(find.byKey(const ValueKey('username')), findsNothing);
      expect(tester.takeException(), isNull);
      await closeApp(tester);
    },
  );

  testWidgets('failed profile reads retry without asking for a new username', (
    tester,
  ) async {
    final store = TestProfileStore()
      ..name = 'Razeem'
      ..failRead = true;
    await openApp(tester, store);
    expect(find.text('Could not load your profile'), findsOneWidget);
    expect(find.byKey(const ValueKey('username')), findsNothing);
    store.failRead = false;
    await tap(tester, 'Try again');
    expect(find.text('Hey, Razeem.'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets(
    'save errors keep onboarding or the old profile until retry succeeds',
    (tester) async {
      final store = TestProfileStore()..failSave = true;
      await openApp(tester, store);
      await tester.enterText(find.byKey(const ValueKey('username')), 'Razeem');
      await tap(tester, 'Let’s go');
      expect(store.name, isNull);
      expect(
        find.text('Could not save your username. Please try again.'),
        findsOneWidget,
      );
      store.failSave = false;
      await tap(tester, 'Let’s go');
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      store.failSave = true;
      await tester.enterText(
        find.byKey(const ValueKey('profile-username')),
        'New name',
      );
      await tap(tester, 'Save changes');
      expect(store.name, 'Razeem');
      expect(
        find.text('Could not save your username. Please try again.'),
        findsOneWidget,
      );
      store.failSave = false;
      await tap(tester, 'Save changes');
      expect(store.name, 'New name');
      await closeApp(tester);
    },
  );

  testWidgets(
    'returning profile waits for storage without flashing onboarding',
    (tester) async {
      final read = Completer<String?>();
      messenger.setMockMethodCallHandler(channel, (_) => read.future);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        BeatrazeemApp(
          studio: Studio(
            audio: TestAudio(),
            discovery: TestDiscovery(),
            room: TestRoom(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Opening your profile…'), findsOneWidget);
      expect(find.byKey(const ValueKey('username')), findsNothing);
      read.complete('Razeem');
      await tester.pumpAndSettle();
      expect(find.text('Hey, Razeem.'), findsOneWidget);
      await closeApp(tester);
    },
  );

  test(
    'invalid saved names fall back to first-time setup; invalid writes never reach storage',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        return 'x' * 25;
      });
      const store = ProfileStore();
      expect(await store.readUsername(), isNull);
      await expectLater(store.saveUsername('  '), throwsFormatException);
      expect(calls, 1);
    },
  );
}
