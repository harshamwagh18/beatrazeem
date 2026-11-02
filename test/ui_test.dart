import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/main.dart';
import 'package:beatrazeem/audio/audio_timing.dart';
import 'package:beatrazeem/core/room_member.dart';
import 'package:beatrazeem/ui/design.dart';
import 'host_microphone_test.dart'
    show TestPrivacyStore, TestRoom, TestAudio, TestDiscovery, TestProfileStore;

void main() {
  setUpAll(() async {
    final fonts = Platform.environment['BEATRAZEEM_FONTS'];
    if (fonts == null) return;
    for (final family in ['sans-serif', 'Roboto']) {
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Medium', 'Bold', 'Black']) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(
              File('$fonts/Roboto/Roboto-$weight.ttf').readAsBytesSync(),
            ),
          ),
        );
      }
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('$fonts/MaterialIcons-Regular.otf').readAsBytesSync(),
          ),
        ),
      );
    await icons.load();
  });

  testWidgets(
    'names and six-digit codes validate; theme switching preserves the session',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.llfbandit.record/messages'),
            (_) async => null,
          );
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.binding.setSurfaceSize(const Size(430, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey();
      final room = TestRoom();
      final audio = TestAudio();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: BeatrazeemApp(
            initialThemeMode: ThemeMode.dark,
            studio: Studio(
              privacyStore: TestPrivacyStore(),
              room: room,
              audio: audio,
              discovery: TestDiscovery(),
              profileStore: TestProfileStore(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(String text) async {
        await tester.ensureVisible(find.text(text));
        await tester.pumpAndSettle();
        await tester.tap(find.text(text));
        await tester.pumpAndSettle();
      }

      Future<void> theme(String name) async {
        await tester.tap(find.byTooltip('Change theme'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }

      Future<void> snapshot(String name) async {
        final directory = Platform.environment['BEATRAZEEM_SCREENSHOTS'];
        if (directory == null) return;
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$directory/$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await snapshot('Welcome');
      await theme('Light');
      await snapshot('Welcome-light');
      await theme('Dark');
      await tap('Let’s go');
      expect(
        find.text('Username must be between 1 and 24 characters.'),
        findsOneWidget,
      );
      expect(find.text('Create a room'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('username')), 'Razeem');
      await tap('Let’s go');
      await tap('Create a room');
      expect(room.connected, isFalse);
      expect(
        find.text('Room name must be between 1 and 36 characters.'),
        findsOneWidget,
      );
      await tap('Join');
      await tester.enterText(
        find.byKey(const ValueKey('room-code')),
        '12ab345678',
      );
      expect(find.text('123456'), findsOneWidget);
      await tap('Host');
      await tester.enterText(
        find.byKey(const ValueKey('room-name')),
        'Midnight lounge',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 1500));
      await tester.pumpAndSettle();

      // Exercise the real animated form resize and theme transition as well as
      // the deterministic reduced-motion path used for the screenshots.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: false);
      await tester.pump();
      Future<void> animatedTap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(target);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
      }

      await animatedTap(find.text('Join'));
      expect(find.text('123456'), findsOneWidget);
      await animatedTap(find.text('Host'));
      expect(find.text('Midnight lounge'), findsOneWidget);
      for (final name in ['Light', 'Dark']) {
        await animatedTap(find.byTooltip('Change theme'));
        await animatedTap(find.text(name).last);
        expect(
          Theme.of(tester.element(find.byType(Scaffold))).brightness,
          name == 'Light' ? Brightness.light : Brightness.dark,
        );
        expect(find.text('Midnight lounge'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 1500));
      await tester.pumpAndSettle();
      await snapshot('Home');
      await tester.tap(find.byTooltip('Privacy & your data'));
      await tester.pumpAndSettle();
      await snapshot('Privacy');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      await snapshot('Profile');
      await tap('Cancel');
      await theme('Light');
      expect(find.text('Midnight lounge'), findsOneWidget);
      expect(find.textContaining('Razeem'), findsWidgets);
      await snapshot('Home-light');
      await theme('Dark');
      await tap('Create a room');
      room.members = const [
        RoomMember(id: 'host', name: 'Razeem', isHost: true),
        RoomMember(id: 'member-1', name: 'Aisha'),
        RoomMember(id: 'member-2', name: 'Arjun'),
      ];
      room.count = 3;
      room.changes.add(null);
      await tester.binding.setSurfaceSize(const Size(430, 1280));
      await tester.pumpAndSettle();
      expect(find.text('Midnight lounge'), findsOneWidget);
      expect(find.text('Razeem (you)'), findsOneWidget);
      expect(find.text('Aisha'), findsOneWidget);
      expect(find.text('Arjun'), findsOneWidget);
      await snapshot('Room');
      await theme('Light');
      expect(room.connected, isTrue);
      expect(find.text('Midnight lounge'), findsOneWidget);
      expect(find.text('Aisha'), findsOneWidget);
      await snapshot('Room-light');
      await theme('Dark');
      await tap('Karaoke');
      await snapshot('Karaoke');
      await tap('Microphone');
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await theme('System');
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.light,
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark,
      );
      expect(room.connected, isTrue);
      room.members = room.members.where((m) => m.name != 'Aisha').toList();
      room.count = 2;
      room.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Aisha'), findsNothing);
      expect(find.text('2/9'), findsOneWidget);
      if (Platform.environment['BEATRAZEEM_SCREENSHOTS'] != null) {
        // Illustrative UI fixture; these numbers are not hardware measurements.
        await tap('Turn on microphone');
        audio.timing = const AudioTiming(
          delayMs: 204,
          offsetMs: 4,
          measured: true,
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('live-delay')),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Live delay'));
        await tester.pumpAndSettle();
        await snapshot('Delay');
        await tap('Stop sharing');
        audio.timing = const AudioTiming();
        await tester.pump(const Duration(seconds: 1));

        await tester.scrollUntilVisible(
          find.text('Adjust speaker timing'),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tap('Adjust speaker timing');
        await tester.ensureVisible(find.text('Choose a reference speaker'));
        await tester.pumpAndSettle();
        await snapshot('Timing-guide');
      }

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('small phone handles long room and member names', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (_) async => null,
        );
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final room = TestRoom();
    await tester.pumpWidget(
      BeatrazeemApp(
        initialThemeMode: ThemeMode.light,
        studio: Studio(
          privacyStore: TestPrivacyStore(),
          room: room,
          audio: TestAudio(),
          discovery: TestDiscovery(),
          profileStore: TestProfileStore(),
        ),
      ),
    );
    Future<void> tap(String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.pumpAndSettle();
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('username')),
      'Alexandria Sunset Sounds',
    );
    await tap('Let’s go');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('room-name')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('room-name')),
      'The beautiful sunset listening room',
    );
    await tap('Create a room');
    await tester.scrollUntilVisible(
      find.text('Alexandria Sunset Sounds (you)'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('both themes use the requested six-color palette', () {
    void expectPalette(Brightness brightness, List<Color> colors) {
      final theme = beatrazeemTheme(brightness: brightness);
      expect(theme.scaffoldBackgroundColor, colors[0]);
      expect(theme.colorScheme.surface, colors[1]);
      expect(theme.colorScheme.primary, colors[2]);
      expect(theme.colorScheme.secondary, colors[3]);
      expect(theme.colorScheme.onSurface, colors[4]);
      expect(theme.colorScheme.onSurfaceVariant, colors[5]);
    }

    expectPalette(Brightness.light, const [
      Color(0xffffffff),
      Color(0xfff5f5f7),
      Color(0xff7c3aed),
      Color(0xffddd6fe),
      Color(0xff18181b),
      Color(0xff71717a),
    ]);
    expectPalette(Brightness.dark, const [
      Color(0xff121216),
      Color(0xff1e1e24),
      Color(0xff7c3aed),
      Color(0xffddd6fe),
      Color(0xfff4f4f5),
      Color(0xffa1a1aa),
    ]);
  });

  testWidgets('signal artwork animates and honors reduced motion', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: false);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: beatrazeemTheme(),
        home: const Scaffold(body: SignalArt(height: 180)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.binding.hasScheduledFrame, isTrue);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
