import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/main.dart';
import 'package:beatrazeem/core/protocol.dart';
import 'package:beatrazeem/audio/audio_timing.dart';
import 'package:beatrazeem/ui/delay_panel.dart';
import 'package:beatrazeem/ui/design.dart';
import 'host_microphone_test.dart'
    show TestPrivacyStore, TestRoom, TestAudio, TestDiscovery, TestProfileStore;

class TimingAudio extends TestAudio {
  AudioTiming nextTiming = const AudioTiming(
    delayMs: 207,
    offsetMs: 7,
    measured: true,
  );
  @override
  Future<AudioTiming> readTiming() async => nextTiming;
}

void main() {
  testWidgets(
    'room refreshes live delay without interrupting capture or membership',
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
      final room = TestRoom(), audio = TimingAudio();
      await tester.pumpWidget(
        BeatrazeemApp(
          studio: Studio(
            privacyStore: TestPrivacyStore(),
            room: room,
            audio: audio,
            discovery: TestDiscovery(),
            profileStore: TestProfileStore()..name = 'Razeem',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('room-name')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const ValueKey('room-name')),
        'Music room',
      );
      Future<void> tap(String label) async {
        await tester.scrollUntilVisible(
          find.text(label),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await tap('Create a room');
      await tap('Turn on microphone');
      audio.onPcm!(Uint8List(frameBytes)..[0] = 10);
      expect(room.sent.single.capturedAt, isNotNull);
      final outputStops = audio.outputStops;
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(find.text('Live delay'));
      await tester.pumpAndSettle();
      expect(find.text('≈ 207 ms'), findsOneWidget);
      expect(find.text('Resync this speaker'), findsNothing);
      audio.nextTiming = const AudioTiming(delayMs: 219, measured: true);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('≈ 219 ms'), findsOneWidget);
      expect(find.text('≈ 207 ms'), findsNothing);
      audio.nextTiming = const AudioTiming();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Measuring…'), findsOneWidget);
      expect(find.text('≈ 0 ms'), findsNothing);
      expect(room.connected, isTrue);
      expect(audio.microphone, isTrue);
      expect(audio.outputStops, outputStops);
      audio.onPcm!(Uint8List(frameBytes)..[0] = 10);
      expect(room.sent, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  test('only fresh speaker measurements are used as playback delay', () {
    final data = <String, dynamic>{
      'running': true,
      'timestampReady': true,
      'fresh': true,
      'estimatedDelayMs': 213.5,
      'timingOffsetMs': 13.5,
      'lateFrames': 2,
      'underruns': 1,
    };
    final report = AudioTiming.fromMap(data);
    expect(report.delayMs, 213.5);
    expect(report.offsetMs, 13.5);
    expect(report.latePackets, 2);
    expect(AudioTiming.fromMap({...data, 'fresh': false}).delayMs, isNull);
    expect(
      AudioTiming.fromMap({...data, 'timestampReady': false}).offsetMs,
      isNull,
    );
    expect(AudioTiming.fromMap({...data, 'running': false}).delayMs, isNull);
    expect(
      AudioTiming.fromMap({...data, 'estimatedDelayMs': double.nan}).delayMs,
      isNull,
    );
    expect(
      AudioTiming.fromMap({...data, 'estimatedDelayMs': -30}).delayMs,
      isNull,
    );
  });

  testWidgets(
    'live delay is read-only and hides unavailable or inactive values',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<void> show(
        AudioTiming timing, {
        bool active = true,
        bool output = true,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: beatrazeemTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: DelayPanel(
                  timing: timing,
                  active: active,
                  outputEnabled: output,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(
        const AudioTiming(
          delayMs: 212,
          offsetMs: 12,
          latePackets: 3,
          underruns: 2,
          measured: true,
        ),
      );
      expect(find.text('≈ 212 ms'), findsOneWidget);
      expect(find.byType(ButtonStyleButton), findsNothing);
      expect(find.text('Timing offset from room'), findsNothing);
      expect(find.text('Planned room buffer'), findsNothing);
      expect(find.text('Wi-Fi round trip'), findsNothing);
      expect(find.text('Late audio packets'), findsNothing);
      expect(find.text('Output interruptions'), findsNothing);
      await show(const AudioTiming());
      expect(find.text('Measuring…'), findsOneWidget);
      expect(find.text('≈ 0 ms'), findsNothing);
      await show(
        const AudioTiming(delayMs: 212, measured: true),
        output: false,
      );
      expect(find.text('Output is off'), findsOneWidget);
      expect(find.text('≈ 212 ms'), findsNothing);
      await show(const AudioTiming(), active: false);
      expect(find.text('Not playing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
