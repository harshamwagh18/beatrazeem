import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/audio/audio_engine.dart';
import 'package:beatrazeem/audio/audio_timing.dart';
import 'package:beatrazeem/core/discovery.dart';
import 'package:beatrazeem/core/protocol.dart';
import 'package:beatrazeem/core/profile_store.dart';
import 'package:beatrazeem/core/privacy_store.dart';
import 'package:beatrazeem/core/privacy_policy.dart';
import 'package:beatrazeem/core/transport.dart';
import 'package:beatrazeem/core/room_member.dart';
import 'package:beatrazeem/main.dart';

class TestPrivacyStore extends PrivacyStore {
  PrivacyConsent? consent = PrivacyConsent(
    noticeVersion: PrivacyPolicy.noticeVersion,
    acceptedAt: DateTime.utc(2026, 11, 2),
    minimumAgeConfirmed: true,
  );
  @override
  Future<PrivacyConsent?> readConsent() async => consent;
  @override
  Future<void> saveConsent({
    required String noticeVersion,
    required bool minimumAgeConfirmed,
  }) async {
    consent = PrivacyConsent(
      noticeVersion: noticeVersion,
      acceptedAt: DateTime.now().toUtc(),
      minimumAgeConfirmed: minimumAgeConfirmed,
    );
  }

  @override
  Future<void> deleteAll() async {
    consent = null;
  }
}

class TestProfileStore extends ProfileStore {
  String? name;
  bool failRead = false, failSave = false;
  int writes = 0;
  @override
  Future<String?> readUsername() async {
    if (failRead) throw StateError('Read failed');
    return name;
  }

  @override
  Future<void> saveUsername(String value) async {
    if (failSave) throw StateError('Save failed');
    name = value;
    writes++;
  }
}

class TestRoom extends RoomTransport {
  bool active = false;
  final sent = <AudioFrame>[];
  @override
  bool get isHost => active;
  @override
  bool get connected => active;
  @override
  Future<void> create(
    String roomCode, {
    required String username,
    required String name,
  }) async {
    active = true;
    code = roomCode;
    roomName = name;
    localMemberId = 'host';
    members = [RoomMember(id: 'host', name: username, isHost: true)];
    changes.add(null);
  }

  @override
  void broadcast(AudioFrame frame) => sent.add(frame);
  @override
  Future<void> close() async {
    active = false;
    await super.close();
  }
}

class TestDiscovery extends RoomDiscovery {
  @override
  Future<void> advertise(String code, int port) async {}
}

class TestAudio extends AudioEngine {
  AudioTiming timing = const AudioTiming();
  @override
  Future<AudioTiming> readTiming() async => timing;
  final played = <AudioFrame>[];
  int outputStops = 0;
  bool microphone = false;
  bool karaoke = false;
  @override
  Future<Map<String, dynamic>?> deviceAudioInfo() async => null;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> startMic() async {
    microphone = true;
  }

  @override
  Future<void> startKaraoke() async {
    karaoke = true;
    microphone = true;
  }

  @override
  Future<void> startDeviceAudio() async {
    microphone = false;
  }

  @override
  Future<void> stopInput() async {
    karaoke = false;
    microphone = false;
  }

  @override
  Future<void> stopOutput() async {
    outputStops++;
  }

  @override
  Future<void> play(
    AudioFrame frame,
    RoomClock clock, {
    required bool host,
  }) async {
    expect(host, isTrue);
    played.add(frame);
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets(
    'host microphone feeds local output and room; switches and mute are respected',
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
      await tester.binding.setSurfaceSize(const Size(430, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final room = TestRoom();
      final audio = TestAudio();
      await tester.pumpWidget(
        BeatrazeemApp(
          initialThemeMode: ThemeMode.dark,
          studio: Studio(
            privacyStore: TestPrivacyStore(),
            room: room,
            audio: audio,
            discovery: TestDiscovery(),
            profileStore: TestProfileStore(),
          ),
        ),
      );
      Future<void> tapText(String text) async {
        final target = find.text(text);
        if (target.evaluate().isEmpty) {
          await tester.drag(find.byType(ListView), const Offset(0, 5000));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            target,
            180,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      void sendMicFrame() => audio.onPcm!(Uint8List(frameBytes)..[0] = 80);

      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('username')), 'Razeem');
      await tapText('Let’s go');
      await tester.enterText(
        find.byKey(const ValueKey('room-name')),
        'Sunset sessions',
      );
      await tapText('Create a room');
      await tapText('Turn on microphone');
      expect(audio.microphone, isTrue);
      expect(room.count, 1); // Host speaker works without another listener.
      sendMicFrame();
      await tester.pump();
      expect(audio.played, hasLength(1));
      expect(room.sent, hasLength(1));
      expect(identical(audio.played.single, room.sent.single), isTrue);

      await tapText('Play mic on host speaker');
      expect(audio.outputStops, 1);
      sendMicFrame();
      await tester.pump();
      expect(audio.played, hasLength(1));
      expect(room.sent, hasLength(2));

      await tapText('Play mic on host speaker');
      final mute = find.byTooltip('Mute');
      await tester.ensureVisible(mute);
      await tester.pumpAndSettle();
      await tester.tap(mute);
      await tester.pumpAndSettle();
      sendMicFrame();
      await tester.pump();
      expect(audio.played, hasLength(1));
      expect(room.sent, hasLength(3));

      await tester.tap(find.byTooltip('Unmute'));
      await tester.pumpAndSettle();
      sendMicFrame();
      await tester.pump();
      expect(audio.played, hasLength(2));
      expect(room.sent, hasLength(4));

      await tapText('Stop sharing');
      sendMicFrame();
      expect(room.sent, hasLength(4));
      await tapText('App audio');
      await tapText('Share device audio');
      sendMicFrame();
      await tester.pump();
      expect(room.sent, hasLength(5));
      expect(audio.played, hasLength(2)); // No duplicate app audio by default.
      await tapText('Stop sharing');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
