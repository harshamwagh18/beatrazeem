import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/main.dart';
import 'package:beatrazeem/core/protocol.dart';
import 'host_microphone_test.dart'
    show TestPrivacyStore, TestRoom, TestAudio, TestDiscovery, TestProfileStore;

void main() {
  testWidgets(
    'Karaoke mixes to the room and host; singer and mic levels stay independent',
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
      await tester.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final room = TestRoom();
      final audio = TestAudio();
      await tester.pumpWidget(
        BeatrazeemApp(
          studio: Studio(
            privacyStore: TestPrivacyStore(),
            room: room,
            audio: audio,
            discovery: TestDiscovery(),
            profileStore: TestProfileStore(),
          ),
        ),
      );
      Future<void> tap(String label) async {
        await tester.scrollUntilVisible(
          find.text(label),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('username')), 'Singer');
      await tap('Let’s go');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('room-name')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const ValueKey('room-name')),
        'Karaoke night',
      );
      await tap('Create a room');
      await tap('Karaoke');
      Future<void> adjust(String key, double value) async {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey(key)),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        tester.widget<Slider>(find.byKey(ValueKey(key))).onChanged!(value);
        await tester.pumpAndSettle();
      }

      await adjust('singer-level', .25);
      expect(audio.singerLevel, .25);
      expect(audio.microphoneLevel, 1);
      await adjust('microphone-level', 1.5);
      expect(audio.singerLevel, .25);
      expect(audio.microphoneLevel, 1.5);
      await tap('Start Karaoke');
      expect(audio.karaoke, isTrue);
      expect(room.source, 'karaoke');
      audio.onPcm!(Uint8List(frameBytes)..[0] = 60);
      await tester.pump();
      expect(room.sent.length, 1);
      expect(audio.played.length, 1);
      await tap('Karaoke mix on this device');
      audio.onPcm!(Uint8List(frameBytes)..[0] = 60);
      await tester.pump();
      expect(room.sent.length, 2);
      expect(audio.played.length, 1);
      await tester.drag(find.byType(ListView), const Offset(0, 2400));
      await tester.pumpAndSettle();
      await tap('Reset mix');
      expect(audio.singerLevel, 1);
      expect(audio.microphoneLevel, 1);
      expect(audio.musicLevel, .7);
      await tap('Stop sharing');
      expect(audio.karaoke, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
