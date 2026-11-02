import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'audio/audio_engine.dart';
import 'audio/audio_timing.dart';
import 'core/capture_health.dart';
import 'core/capture_timeline.dart';
import 'core/discovery.dart';
import 'core/protocol.dart';
import 'core/profile_store.dart';
import 'core/transport.dart';
import 'core/room_member.dart';
import 'ui/design.dart';
import 'ui/profile_dialog.dart';
import 'ui/delay_panel.dart';

void main() => runApp(const BeatrazeemApp());

class BeatrazeemApp extends StatefulWidget {
  const BeatrazeemApp({
    super.key,
    this.studio,
    this.initialThemeMode = ThemeMode.system,
  });
  final Studio? studio;
  final ThemeMode initialThemeMode;
  @override
  State<BeatrazeemApp> createState() => _BeatrazeemAppState();
}

class _BeatrazeemAppState extends State<BeatrazeemApp> {
  late ThemeMode mode = widget.initialThemeMode;
  @override
  Widget build(BuildContext context) => _Appearance(
    mode: mode,
    onChanged: (value) => setState(() => mode = value),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Beatrazeem',
      theme: beatrazeemTheme(brightness: Brightness.light),
      darkTheme: beatrazeemTheme(brightness: Brightness.dark),
      themeMode: mode,
      themeAnimationDuration:
          WidgetsBinding
              .instance
              .platformDispatcher
              .accessibilityFeatures
              .disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 320),
      themeAnimationCurve: Curves.easeInOutCubic,
      home: widget.studio ?? const Studio(),
    ),
  );
}

class _Appearance extends InheritedWidget {
  const _Appearance({
    required this.mode,
    required this.onChanged,
    required super.child,
  });
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;
  static _Appearance? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Appearance>();
  @override
  bool updateShouldNotify(_Appearance oldWidget) => oldWidget.mode != mode;
}

class Studio extends StatefulWidget {
  const Studio({
    super.key,
    this.room,
    this.discovery,
    this.audio,
    this.profileStore = const ProfileStore(),
  });
  final RoomTransport? room;
  final RoomDiscovery? discovery;
  final AudioEngine? audio;
  final ProfileStore profileStore;
  @override
  State<Studio> createState() => _StudioState();
}

class _StudioState extends State<Studio> with WidgetsBindingObserver {
  late final room = widget.room ?? RoomTransport();
  late final discovery = widget.discovery ?? RoomDiscovery();
  late final audio = widget.audio ?? AudioEngine();
  final captureHealth = CaptureHealth();
  final captureTimeline = CaptureTimeline();
  final codeInput = TextEditingController();
  final usernameInput = TextEditingController();
  final roomNameInput = TextEditingController();
  final profileForm = GlobalKey<FormState>();
  final roomForm = GlobalKey<FormState>();
  String? username;
  String? usernameSaveError;
  bool profileLoaded = false;
  bool profileLoadFailed = false;
  bool joining = false;
  StreamSubscription? updates;
  Timer? testTone;
  Timer? captureCheck;
  Timer? timingCheck;
  AudioTiming audioTiming = const AudioTiming();
  bool checkingTiming = false;
  int lastMeterUpdateUs = 0;
  int timingVersion = 0;
  Map<String, dynamic>? deviceInfo;
  String mode = 'mic';
  bool busy = false, sending = false, monitor = false, mutedOutput = false;
  bool micMonitor = true;
  bool karaokeMonitor = true;
  bool get hostPlayback =>
      room.source == 'test' ||
      (mode == 'karaoke'
          ? karaokeMonitor
          : mode == 'mic'
          ? micMonitor
          : monitor);
  String? error;
  int seq = 0, nextPlayAt = 0;
  double level = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    updates = room.changes.stream.listen((_) {
      if (mounted) setState(() {});
    });
    room.onAudio = (frame) {
      if (!mutedOutput) {
        unawaited(audio.play(frame, room.clock, host: false));
      }
    };
    room.onSource = (source) {
      if (source == 'idle') {
        timingVersion++;
        audioTiming = const AudioTiming();
        unawaited(audio.stopOutput());
      }
    };
    room.onEnded = (message) {
      unawaited(audio.stopOutput());
      unawaited(discovery.stop());
      if (mounted) setState(() => error = message);
    };
    audio.onPcm = _broadcast;
    audio.onCapturedPcm = (pcm, time) => _broadcast(pcm, capturedAtUs: time);
    audio.onError = (message) {
      if (mounted) {
        setState(() => error = message);
        unawaited(_stop());
      }
    };
    unawaited(_loadDeviceInfo());
    unawaited(_loadProfile());
    timingCheck = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_refreshTiming()),
    );
  }

  Future<void> _refreshTiming() async {
    if (!room.connected || checkingTiming || !mounted) return;
    checkingTiming = true;
    final version = timingVersion;
    final code = room.code;
    try {
      final next = await audio.readTiming();
      if (mounted &&
          room.connected &&
          room.code == code &&
          timingVersion == version) {
        setState(() => audioTiming = next);
      }
    } catch (_) {
      if (mounted) setState(() => audioTiming = const AudioTiming());
    } finally {
      checkingTiming = false;
    }
  }

  Future<void> _loadProfile() async {
    setState(() => profileLoadFailed = false);
    try {
      final saved = await widget.profileStore.readUsername();
      if (!mounted) return;
      setState(() {
        username = saved;
        usernameInput.text = saved ?? '';
        profileLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => profileLoadFailed = true);
    }
  }

  Future<void> _saveUsername(String name) async {
    await widget.profileStore.saveUsername(name);
    if (!mounted) return;
    setState(() {
      username = name;
      usernameInput.text = name;
    });
    room.rename(name);
  }

  Future<void> _openProfile() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProfileDialog(username: username!, onSave: _saveUsername),
    );
    if (mounted && saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Username saved')));
    }
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final info = await audio.deviceAudioInfo();
      if (mounted) setState(() => deviceInfo = info);
    } catch (_) {
      /* Capture itself reports any unavailable platform support. */
    }
  }

  void _checkCapture() {
    if (!sending || room.source != 'device') return;
    room.setCaptureStatus(captureHealth.status(room.clock.now));
  }

  void _broadcast(Uint8List pcm, {int? capturedAtUs}) {
    if (!sending) return;
    if (room.source == 'device') {
      captureHealth.observe(pcm, room.clock.now);
      _checkCapture();
    }
    final now = room.clock.now;
    final captureAt = capturedAtUs ?? now - frameUs;
    final playAt = captureTimeline.schedule(
      capturedAtUs: captureAt,
      nowUs: now,
    );
    if (playAt == null) return;
    final frame = AudioFrame(seq++, playAt, pcm, capturedAt: captureAt);
    nextPlayAt = playAt + frameUs;
    room.broadcast(frame);
    if (hostPlayback && !mutedOutput) {
      unawaited(audio.play(frame, room.clock, host: true));
    }
    final bytes = ByteData.sublistView(pcm);
    double peak = 0;
    for (var i = 0; i < pcm.length; i += 32) {
      peak = max(peak, bytes.getInt16(i, Endian.little).abs() / 32768);
    }
    if (mounted && now - lastMeterUpdateUs >= 50000) {
      lastMeterUpdateUs = now;
      setState(() => level = peak);
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _create() async {
    if (!(roomForm.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await _action(() async {
      await discovery.prepareHost();
      await audio.initialize();
      await audio.synchronizeClock(room.clock);
      try {
        await room.create(
          createRoomCode(),
          username: username!,
          name: roomNameInput.text,
        );
        await discovery.advertise(room.code!, room.port);
      } catch (_) {
        await room.close();
        await discovery.stop();
        rethrow;
      }
    });
  }

  Future<void> _join() async {
    if (!(roomForm.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await _action(() async {
      final code = codeInput.text.trim();
      if (!validRoomCode(code)) {
        throw const FormatException('Enter the 6-digit room code.');
      }
      await audio.initialize();
      await audio.synchronizeClock(room.clock);
      try {
        final endpoint = await discovery.find(code);
        await room.join(endpoint.$1, endpoint.$2, code, username: username!);
      } catch (_) {
        await room.close();
        await discovery.stop();
        rethrow;
      }
    });
  }

  Future<void> _start() => _action(() async {
    if (mode != 'mic' && deviceInfo?['supported'] == false) {
      throw Exception(
        'App audio sharing needs Android 10 or newer. This phone can still share its microphone or join a room.',
      );
    }
    nextPlayAt = 0;
    seq = 0;
    captureTimeline.reset();
    setState(() => sending = true);
    room.setSource(mode);
    try {
      if (mode == 'mic') {
        await audio.startMic();
      } else if (mode == 'karaoke') {
        await audio.startKaraoke();
      } else {
        await audio.startDeviceAudio();
      }
      if (mode == 'device') {
        captureHealth.start(room.clock.now);
        _checkCapture();
        captureCheck = Timer.periodic(
          const Duration(seconds: 1),
          (_) => _checkCapture(),
        );
      }
    } catch (_) {
      await _stop();
      rethrow;
    }
  });
  Future<void> _stop() async {
    timingVersion++;
    testTone?.cancel();
    testTone = null;
    captureCheck?.cancel();
    captureCheck = null;
    captureHealth.stop();
    room.setCaptureStatus('idle');
    if (mounted) {
      setState(() {
        sending = false;
        level = 0;
        audioTiming = const AudioTiming();
      });
    }
    await audio.stopInput();
    await audio.stopOutput();
    if (room.isHost) room.setSource('idle');
  }

  Future<void> _leave() => _action(() async {
    await _stop();
    await discovery.stop();
    await room.close();
    monitor = false;
    micMonitor = true;
    karaokeMonitor = true;
  });
  Future<void> _test() => _action(() async {
    if (sending) await _stop();
    nextPlayAt = 0;
    seq = 0;
    captureTimeline.reset();
    setState(() => sending = true);
    room.setSource('test');
    var count = 0;
    final toneStart = room.clock.now;
    testTone = Timer.periodic(const Duration(microseconds: frameUs), (_) {
      if (count >= 2000000 ~/ frameUs) {
        testTone?.cancel();
        testTone = Timer(
          Duration(microseconds: max(0, nextPlayAt - room.clock.now) + 50000),
          () => unawaited(_stop()),
        );
        return;
      }
      final pcm = Uint8List(frameBytes);
      final data = ByteData.sublistView(pcm);
      for (var i = 0; i < frameSamples; i++) {
        final sample = count * frameSamples + i;
        // A short chime each second; fades prevent clicks.
        final phase = sample % sampleRate;
        final envelope = phase < 12000 ? sin(pi * phase / 12000) * .15 : 0.0;
        data.setInt16(
          i * 2,
          (sin(2 * pi * 660 * sample / sampleRate) * envelope * 32767).round(),
          Endian.little,
        );
      }
      _broadcast(pcm, capturedAtUs: toneStart + count * frameUs);
      count++;
    });
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android's device-capture foreground service keeps running in other apps.
    if (state == AppLifecycleState.paused && sending && mode == 'mic') {
      unawaited(_stop());
      if (mounted) {
        setState(
          () => error =
              'Microphone sharing paused. Keep Beatrazeem open while using the mic.',
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    testTone?.cancel();
    captureCheck?.cancel();
    timingCheck?.cancel();
    updates?.cancel();
    unawaited(discovery.stop());
    unawaited(room.close());
    unawaited(audio.dispose());
    codeInput.dispose();
    usernameInput.dispose();
    roomNameInput.dispose();
    super.dispose();
  }

  String? _nameError(String? value, int limit, String label) {
    try {
      roomText(value ?? '', limit: limit, label: label);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  Future<void> _continue() async {
    if (busy || !(profileForm.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final name = roomText(usernameInput.text, limit: 24, label: 'Username');
    setState(() => usernameSaveError = null);
    await _action(() async {
      try {
        await _saveUsername(name);
      } catch (_) {
        if (mounted) {
          setState(
            () => usernameSaveError =
                'Could not save your username. Please try again.',
          );
        }
      }
    });
  }

  AppPalette get c => AppPalette.of(context);
  Duration get motion => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    final page = !profileLoaded
        ? 'loading-profile'
        : username == null
        ? 'welcome'
        : room.connected
        ? 'room'
        : 'home';
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: c.background,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 12, 14, 10),
                    child: _header(),
                  ),
                  if (busy) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: Entrance(
                      key: ValueKey('entrance-$page'),
                      child: ListView(
                        key: ValueKey(page),
                        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
                        children: [
                          if (error != null) ...[
                            _errorNotice(),
                            const SizedBox(height: 18),
                          ],
                          if (!profileLoaded)
                            _profileLoading()
                          else if (username == null)
                            ..._welcome()
                          else if (!room.connected)
                            ..._lobby()
                          else
                            ..._room(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
    children: [
      const Expanded(child: BrandMark()),
      if (username != null)
        IconButton(
          tooltip: 'Profile',
          onPressed: busy ? null : _openProfile,
          icon: InitialAvatar(username!, size: 30),
        ),
      PopupMenuButton<ThemeMode>(
        tooltip: 'Change theme',
        initialValue: _Appearance.of(context)?.mode ?? ThemeMode.system,
        onSelected: (value) => _Appearance.of(context)?.onChanged(value),
        icon: Icon(
          Theme.of(context).brightness == Brightness.dark
              ? Icons.dark_mode_outlined
              : Icons.light_mode_outlined,
          color: c.muted,
          size: 21,
        ),
        itemBuilder: (_) => [
          for (final entry in [
            (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
            (ThemeMode.light, 'Light', Icons.light_mode_outlined),
            (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
          ])
            PopupMenuItem(
              value: entry.$1,
              child: Row(
                children: [
                  Icon(entry.$3, size: 19),
                  const SizedBox(width: 12),
                  Text(entry.$2),
                  const Spacer(),
                  if ((_Appearance.of(context)?.mode ?? ThemeMode.system) ==
                      entry.$1)
                    Icon(Icons.check_rounded, color: c.accent, size: 18),
                ],
              ),
            ),
        ],
      ),
      IconButton(
        tooltip: 'How it works',
        onPressed: _help,
        icon: Icon(Icons.help_outline_rounded, color: c.muted, size: 21),
      ),
    ],
  );

  Widget _profileLoading() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 80),
    child: Column(
      children: [
        if (profileLoadFailed) ...[
          _sectionTitle('Could not load your profile'),
          const SizedBox(height: 12),
          _note('Try again to open your saved profile.'),
          const SizedBox(height: 20),
          FilledButton(onPressed: _loadProfile, child: const Text('Try again')),
        ] else ...[
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          _note('Opening your profile…'),
        ],
      ],
    ),
  );

  Widget _eyebrow(String text, {Color? color}) => Text(
    text,
    style: TextStyle(
      color: color ?? c.accentText,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 2.0,
    ),
  );

  Widget _headline(String text, {double size = 42, Color? color}) => Text(
    text,
    style: TextStyle(
      color: color ?? c.text,
      fontSize: size,
      height: 1.04,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.8,
    ),
  );

  Widget _note(String text, {Color? color}) => Text(
    text,
    style: TextStyle(color: color ?? c.muted, fontSize: 13, height: 1.5),
  );

  Widget _sectionTitle(String text, {Widget? trailing}) => Row(
    children: [
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            color: c.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -.5,
          ),
        ),
      ),
      ?trailing,
    ],
  );

  Widget _errorNotice() => Surface(
    color: c.tint,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Let’s check that',
          trailing: Icon(Icons.info_outline, color: c.accent, size: 20),
        ),
        const SizedBox(height: 8),
        _note(error!, color: c.text),
        TextButton(
          onPressed: () => setState(() => error = null),
          child: const Text('Dismiss'),
        ),
      ],
    ),
  );

  List<Widget> _welcome() => [
    const SizedBox(height: 14),
    Row(
      children: [
        Expanded(child: _eyebrow('SOUND BETTER. TOGETHER.')),
        const SizedBox(width: 10),
        Icon(Icons.auto_awesome_rounded, size: 18, color: c.accent),
      ],
    ),
    const SizedBox(height: 22),
    _headline('Small room.\nBig energy.', size: 49),
    const SizedBox(height: 12),
    _note('Your music. Your voice. Every speaker in on it.'),
    const SignalArt(height: 210),
    Entrance(
      delay: const Duration(milliseconds: 100),
      child: Surface(
        child: Form(
          key: profileForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(
                'First, what’s your name?',
                trailing: _miniTag('01 / 02'),
              ),
              const SizedBox(height: 6),
              _note('Choose once. Change it anytime in Profile.'),
              const SizedBox(height: 20),
              TextFormField(
                key: const ValueKey('username'),
                controller: usernameInput,
                enabled: !busy,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                maxLength: 24,
                validator: (v) => _nameError(v, 24, 'Username'),
                decoration: const InputDecoration(
                  labelText: 'Your username',
                  hintText: 'What should we call you?',
                  counterText: '',
                  prefixIcon: Icon(Icons.person_outline_rounded, size: 21),
                ),
                onFieldSubmitted: (_) => _continue(),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: busy ? null : _continue,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Let’s go'),
                    SizedBox(width: 12),
                    Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
              if (usernameSaveError != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    usernameSaveError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Saved on this phone. No account needed.',
                  style: TextStyle(color: c.muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    const SizedBox(height: 26),
    _connectionNote(),
  ];

  Widget _miniTag(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: c.tint,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: c.accentText,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: .7,
      ),
    ),
  );

  List<Widget> _lobby() => [
    const SizedBox(height: 10),
    _note('Hey, $username.'),
    const SizedBox(height: 10),
    _headline('Set the mood.\nShare the sound.'),
    const SizedBox(height: 22),
    Surface(
      padding: 18,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _eyebrow('THE TOGETHER EFFECT'),
                const SizedBox(height: 10),
                Text(
                  'One room.\nEvery speaker.',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 22,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.6,
                  ),
                ),
                const SizedBox(height: 10),
                _note('Connect nearby.\nPlay out loud.'),
              ],
            ),
          ),
          const Expanded(child: SignalArt(height: 152)),
        ],
      ),
    ),
    const SizedBox(height: 24),
    _sectionTitle('Make your move', trailing: _miniTag('02 / 02')),
    const SizedBox(height: 14),
    _modeSelector(),
    const SizedBox(height: 16),
    Surface(
      child: Form(
        key: roomForm,
        child: _resizing(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _iconTile(
                    joining ? Icons.login_rounded : Icons.add_rounded,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      joining
                          ? 'Your people are waiting.'
                          : 'You set the rhythm.',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _note(
                joining
                    ? 'Connect this phone to the creator’s hotspot in Android Wi-Fi settings, then enter the six-digit room code.'
                    : 'Turn on this phone’s hotspot in Android settings. Connect every listener to it, then create your room.',
              ),
              const SizedBox(height: 22),
              if (!joining)
                TextFormField(
                  key: const ValueKey('room-name'),
                  controller: roomNameInput,
                  maxLength: 36,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Room name',
                    hintText: 'e.g. Midnight lounge',
                    counterText: '',
                  ),
                  validator: (v) => _nameError(v, 36, 'Room name'),
                  onFieldSubmitted: (_) {
                    if (!busy) _create();
                  },
                )
              else
                TextFormField(
                  key: const ValueKey('room-code'),
                  controller: codeInput,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 8,
                  ),
                  decoration: const InputDecoration(
                    labelText: '6-digit room code',
                    hintText: '000000',
                    counterText: '',
                  ),
                  validator: (v) => validRoomCode(v?.trim() ?? '')
                      ? null
                      : 'Enter the 6-digit room code.',
                  onFieldSubmitted: (_) {
                    if (!busy) _join();
                  },
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : joining
                    ? _join
                    : _create,
                icon: Icon(
                  joining ? Icons.arrow_forward_rounded : Icons.add_rounded,
                  size: 20,
                ),
                label: Text(joining ? 'Join room' : 'Create a room'),
              ),
            ],
          ),
        ),
      ),
    ),
    const SizedBox(height: 22),
    Row(
      children: [
        Expanded(child: _feature(Icons.mic_none_rounded, 'Live mic')),
        const SizedBox(width: 10),
        Expanded(child: _feature(Icons.music_note_rounded, 'App audio')),
        const SizedBox(width: 10),
        Expanded(child: _feature(Icons.bluetooth_rounded, 'Speakers')),
      ],
    ),
    const SizedBox(height: 26),
    _connectionNote(),
  ];

  Widget _resizing({required Widget child}) =>
      MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          duration: motion,
          alignment: Alignment.topCenter,
          curve: Curves.easeInOutCubic,
          child: child,
        );

  Widget _modeSelector() => Container(
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: c.line),
    ),
    child: Row(
      children: [
        Expanded(
          child: _choice(
            'Host',
            Icons.add_circle_outline_rounded,
            !joining,
            () => setState(() => joining = false),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: _choice(
            'Join',
            Icons.arrow_forward_rounded,
            joining,
            () => setState(() => joining = true),
          ),
        ),
      ],
    ),
  );

  Widget _choice(
    String title,
    IconData icon,
    bool selected,
    VoidCallback? onTap,
  ) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: motion,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: selected ? c.onAccent : c.muted),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    color: selected ? c.onAccent : c.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _feature(IconData icon, String label) => Surface(
    padding: 12,
    child: Column(
      children: [
        Icon(icon, color: c.accent, size: 22),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _iconTile(IconData icon, {double size = 44}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: c.tint,
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: Icon(icon, size: size * .5, color: c.accent),
  );

  Widget _connectionNote() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.wifi_rounded, color: c.muted, size: 13),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          'Creator’s hotspot. One room. No uploads.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontSize: 10, letterSpacing: .2),
        ),
      ),
    ],
  );

  List<Widget> _room() => [
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(
          child: _eyebrow(
            room.isHost ? 'YOUR ROOM / CREATOR' : 'YOUR ROOM / LISTENER',
          ),
        ),
        const SizedBox(width: 12),
        StatusPill(
          room.source == 'idle' ? 'STANDBY' : 'LIVE',
          active: room.source != 'idle',
        ),
      ],
    ),
    const SizedBox(height: 18),
    _headline(room.roomName ?? 'Listening room', size: 35),
    const SizedBox(height: 8),
    _note(
      '${room.count} ${room.count == 1 ? 'person' : 'people'} connected. One shared moment.',
    ),
    const SizedBox(height: 22),
    _inviteCard(),
    const SizedBox(height: 20),
    if (room.isHost) _creatorControls() else _listenerControls(),
    const SizedBox(height: 22),
    _members(),
    const SizedBox(height: 20),
    _output(),
    const SizedBox(height: 16),
    TextButton.icon(
      onPressed: busy ? null : _leave,
      icon: const Icon(Icons.logout_rounded, size: 17),
      label: Text(room.isHost ? 'End room' : 'Leave room'),
    ),
    const SizedBox(height: 12),
    _connectionNote(),
  ];

  Widget _inviteCard() => Surface(
    color: c.accent,
    padding: 20,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _eyebrow('THE KEY TO YOUR ROOM', color: c.onAccent),
              const SizedBox(height: 10),
              Semantics(
                label: 'Room code ${room.code!.split('').join(' ')}',
                child: ExcludeSemantics(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      room.code!,
                      style: TextStyle(
                        color: c.onAccent,
                        fontSize: 35,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Six digits. Bring everyone in.',
                style: TextStyle(
                  color: c.onAccent.withValues(alpha: .8),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        IconButton.filledTonal(
          tooltip: 'Copy room code',
          style: IconButton.styleFrom(
            backgroundColor: c.onAccent.withValues(alpha: .12),
            foregroundColor: c.onAccent,
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: room.code!));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Room code copied'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          icon: const Icon(Icons.copy_rounded, size: 21),
        ),
      ],
    ),
  );

  Widget _creatorControls() => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Control the energy',
          trailing: Icon(Icons.tune_rounded, color: c.accent, size: 20),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            children: [
              Expanded(
                child: _source('mic', Icons.mic_none_rounded, 'Microphone'),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _source('device', Icons.music_note_rounded, 'App audio'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _source('karaoke', Icons.lyrics_outlined, 'Karaoke'),
        const SizedBox(height: 22),
        Row(
          children: [
            _iconTile(
              sending
                  ? Icons.graphic_eq_rounded
                  : mode == 'mic'
                  ? Icons.mic_none_rounded
                  : Icons.music_note_rounded,
              size: 48,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sending ? 'You’re live.' : 'Ready to go live?',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    mode == 'mic'
                        ? 'Your voice, amplified.'
                        : mode == 'karaoke'
                        ? 'Your voice. Your backing track.'
                        : 'Your soundtrack, shared.',
                    style: TextStyle(color: c.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.line),
          ),
          child: SoundWave(level: level, active: sending),
        ),
        const SizedBox(height: 16),
        if (mode == 'mic')
          _note(
            'Speak into your phone. Your speaker and your room will hear you.',
          )
        else if (mode == 'karaoke') ...[
          _karaokeControls(),
        ] else ...[
          _note('Share sound from apps that allow Android audio capture.'),
          const SizedBox(height: 8),
          _note(
            'The original app on this phone plays earlier than the room. For aligned listening, use the joined phones as speakers.',
          ),
          if (deviceInfo != null) ...[
            const SizedBox(height: 8),
            _note(
              'Android ${deviceInfo!['androidVersion']} • ${deviceInfo!['model']}',
            ),
          ],
          if (sending && room.source == 'device') ...[
            const SizedBox(height: 10),
            _captureNotice(creator: true),
          ],
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy
              ? null
              : sending
              ? () => _action(_stop)
              : _start,
          icon: Icon(
            sending
                ? Icons.stop_rounded
                : mode == 'mic'
                ? Icons.mic_rounded
                : Icons.play_arrow_rounded,
            size: 22,
          ),
          label: Text(
            sending
                ? 'Stop sharing'
                : mode == 'mic'
                ? 'Turn on microphone'
                : mode == 'karaoke'
                ? 'Start Karaoke'
                : 'Share device audio',
          ),
        ),
        Center(
          child: TextButton.icon(
            onPressed: busy || room.source == 'test' ? null : _test,
            icon: const Icon(Icons.surround_sound_rounded, size: 17),
            label: const Text(
              'Test room speakers',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        if (sending && room.source != 'test')
          _note('The test stops sharing. Start it again after the chime.'),
      ],
    ),
  );

  void _setKaraokeLevel({double? singer, double? microphone, double? music}) {
    final update = audio.setKaraokeLevels(
      singer: singer,
      microphone: microphone,
      music: music,
    );
    setState(() {});
    unawaited(
      update.catchError((Object e) {
        if (mounted) {
          setState(() => error = 'Could not update Karaoke levels: $e');
        }
      }),
    );
  }

  Widget _karaokeControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _note(
        '1. Start Karaoke and allow microphone and audio sharing.\n2. Open a music app and play a song.\n3. Sing into this phone; your room hears the mix.',
      ),
      const SizedBox(height: 14),
      _mixSlider(
        'Singer level',
        'singer-level',
        audio.singerLevel,
        1.5,
        (v) => _setKaraokeLevel(singer: v),
      ),
      _note(
        '100% is the original singer level. Lower it to reduce vocals or raise it for emphasis. Best with stereo songs; some instruments may change too. This is a vocal-reduction effect, not isolated singer volume.',
      ),
      const SizedBox(height: 12),
      _mixSlider(
        'Backing music',
        'music-level',
        audio.musicLevel,
        1,
        (v) => _setKaraokeLevel(music: v),
      ),
      _mixSlider(
        'Your microphone',
        'microphone-level',
        audio.microphoneLevel,
        2,
        (v) => _setKaraokeLevel(microphone: v),
      ),
      TextButton.icon(
        onPressed: () => _setKaraokeLevel(singer: 1, microphone: 1, music: .7),
        icon: const Icon(Icons.restart_alt_rounded, size: 18),
        label: const Text('Reset mix'),
      ),
      _note(
        'Keep the microphone away from speakers to avoid feedback. The shared mix has a short delay. Only apps that allow audio capture can supply the backing track; this cannot change the original song playing in the source app.',
      ),
    ],
  );

  Widget _mixSlider(
    String title,
    String key,
    double value,
    double maximum,
    ValueChanged<double> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '${(value * 100).round()}%',
            style: TextStyle(color: c.accentText),
          ),
        ],
      ),
      Slider(
        key: ValueKey(key),
        value: value,
        min: 0,
        max: maximum,
        divisions: (maximum * 20).round(),
        label: '${(value * 100).round()}%',
        semanticFormatterCallback: (v) => '$title ${(v * 100).round()} percent',
        onChanged: onChanged,
      ),
    ],
  );

  Widget _source(String value, IconData icon, String title) => _choice(
    title,
    icon,
    mode == value,
    busy || sending ? null : () => setState(() => mode = value),
  );

  Widget _listenerControls() => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'In the moment',
          trailing: Icon(Icons.headphones_rounded, color: c.accent, size: 22),
        ),
        const SignalArt(height: 160),
        Text(
          room.source == 'idle'
              ? 'The stage is set.'
              : 'You’re part of the sound.',
          style: TextStyle(
            color: c.text,
            fontSize: 25,
            fontWeight: FontWeight.w800,
            letterSpacing: -.8,
          ),
        ),
        const SizedBox(height: 10),
        if (room.source == 'device')
          _captureNotice(creator: false)
        else
          _note(
            room.source == 'idle'
                ? 'Waiting for the creator to start sharing.'
                : room.source == 'karaoke'
                ? 'Karaoke is live: backing music and the creator’s microphone.'
                : room.source == 'mic'
                ? 'The creator’s microphone is sharing.'
                : 'The creator is sending a test chime.',
          ),
        const SizedBox(height: 10),
        SoundWave(level: 0, active: room.source != 'idle'),
        if (room.audioFramesReceived > 0)
          _note('Room audio data has reached this phone.'),
        const SizedBox(height: 8),
        Text(
          room.clock.ready
              ? 'Playback timing connected'
              : 'Checking playback timing…',
          style: TextStyle(color: c.accentText, fontSize: 11),
        ),
      ],
    ),
  );

  Widget _members() => Surface(
    padding: 18,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('In this room', trailing: _miniTag('${room.count}/9')),
        const SizedBox(height: 10),
        if (room.members.isEmpty)
          _note('Update every phone to see member names.')
        else
          for (var i = 0; i < room.members.length; i++) ...[
            Entrance(
              key: ValueKey(room.members[i].id),
              delay: Duration(milliseconds: i * 50),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    InitialAvatar(
                      room.members[i].name,
                      host: room.members[i].isHost,
                      size: 42,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${room.members[i].name}${room.members[i].id == room.localMemberId ? ' (you)' : ''}',
                            style: TextStyle(
                              color: c.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            room.members[i].isHost
                                ? 'Running the room'
                                : 'Here for the sound',
                            style: TextStyle(color: c.muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      room.members[i].isHost
                          ? Icons.workspace_premium_outlined
                          : Icons.headphones_rounded,
                      size: 19,
                      color: room.members[i].isHost ? c.accent : c.muted,
                    ),
                  ],
                ),
              ),
            ),
            if (i < room.members.length - 1) const Divider(height: 1),
          ],
        if (room.count == 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _note('Share the code above to bring your people in.'),
          ),
      ],
    ),
  );

  Widget _output() => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Your speaker',
          trailing: IconButton(
            tooltip: mutedOutput ? 'Unmute' : 'Mute',
            onPressed: () {
              setState(() => mutedOutput = !mutedOutput);
              if (mutedOutput) unawaited(audio.stopOutput());
            },
            icon: Icon(
              mutedOutput ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: c.accent,
            ),
          ),
        ),
        _note(
          'Uses the media output selected in Android, including Bluetooth speakers.',
        ),
        if (room.isHost)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              mode == 'karaoke'
                  ? 'Karaoke mix on this device'
                  : mode == 'mic'
                  ? 'Play mic on host speaker'
                  : 'Play on this device too',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              mode == 'karaoke'
                  ? 'The source app may still be audible. Switch this off and use joined speakers to hear only the Karaoke mix.'
                  : mode == 'mic'
                  ? 'Keep the phone away from the speaker to avoid feedback.'
                  : 'Adds a delayed copy. Leave off while the source app is audible to avoid echo.',
              style: TextStyle(color: c.muted, fontSize: 11),
            ),
            value: hostPlayback,
            onChanged: (v) {
              setState(() {
                if (mode == 'karaoke') {
                  karaokeMonitor = v;
                } else if (mode == 'mic') {
                  micMonitor = v;
                } else {
                  monitor = v;
                }
              });
              if (!v) unawaited(audio.stopOutput());
            },
          ),
        Row(
          children: [
            Icon(Icons.volume_down_rounded, color: c.muted, size: 20),
            Expanded(
              child: Slider(
                value: audio.volume,
                onChanged: (v) => setState(() => audio.setVolume(v)),
              ),
            ),
            Text(
              '${(audio.volume * 100).round()}%',
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DelayPanel(
          timing: audioTiming,
          active: room.source != 'idle',
          outputEnabled: !mutedOutput && (!room.isHost || hostPlayback),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'Adjust speaker timing',
            style: TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            'Tap for a step-by-step guide',
            style: TextStyle(color: c.muted, fontSize: 11),
          ),
          children: [
            _timingStep(
              '1',
              'Choose a reference speaker',
              'Keep the slowest joined phone at 0 ms. Add delay to the faster phones to match it. Stop sharing before changing the adjustment.',
            ),
            _timingStep(
              '2',
              'Play the room test',
              room.isHost
                  ? 'Tap Play timing chime below. This stops current sharing and plays the same chime through the room, including this phone.'
                  : 'Ask the creator to tap Test room speakers. Listen for two separate beats instead of one.',
            ),
            if (room.isHost)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  onPressed: busy || room.source == 'test' ? null : _test,
                  icon: const Icon(Icons.surround_sound_rounded, size: 18),
                  label: const Text('Play timing chime'),
                ),
              ),
            _timingStep(
              '3',
              'Move this speaker into time',
              'If this phone plays first, stop sharing and add 10 ms of delay. Replay the chime. If it plays last, leave it at 0 ms and delay the other phones.',
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Less delay',
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
                Text(
                  'Later (+)',
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ],
            ),
            Slider(
              value: audio.correctionMs.toDouble(),
              min: 0,
              max: 500,
              divisions: 50,
              label: '${audio.correctionMs} ms',
              semanticFormatterCallback: (value) => value == 0
                  ? 'No adjustment'
                  : '${value.abs().round()} milliseconds ${value < 0 ? 'earlier' : 'later'}',
              onChanged: room.source != 'idle'
                  ? null
                  : (v) => setState(() => audio.correctionMs = v.round()),
            ),
            Text(
              audio.correctionMs == 0
                  ? '0 ms · No adjustment'
                  : '${audio.correctionMs > 0 ? '+' : ''}${audio.correctionMs} ms · This phone plays ${audio.correctionMs < 0 ? 'earlier' : 'later'}',
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: room.source != 'idle' || audio.correctionMs <= 0
                      ? null
                      : () => setState(
                          () => audio.correctionMs = (audio.correctionMs - 10)
                              .clamp(0, 500),
                        ),
                  child: const Text('Less delay 10 ms'),
                ),
                OutlinedButton(
                  onPressed: room.source != 'idle' || audio.correctionMs >= 500
                      ? null
                      : () => setState(
                          () => audio.correctionMs = (audio.correctionMs + 10)
                              .clamp(0, 500),
                        ),
                  child: const Text('Later 10 ms'),
                ),
                TextButton(
                  onPressed: room.source != 'idle' || audio.correctionMs == 0
                      ? null
                      : () => setState(() => audio.correctionMs = 0),
                  child: const Text('Reset to 0 ms'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _timingStep(
              '4',
              'Listen, repeat, then play',
              'Adjustments are locked while audio is playing to prevent jumps and gaps. Stop sharing, change the delay, then replay the chime. Aim to hear one beat. Repeat on each phone, then ask the creator to start sharing again.',
            ),
            _note(
              'This changes only this phone. Compare joined speakers, not the creator’s original YouTube/Spotify sound. Delay faster phones to match the slowest; audio cannot play before it arrives. Recheck after changing speakers or Bluetooth routes.',
            ),
            const SizedBox(height: 14),
          ],
        ),
      ],
    ),
  );

  Widget _timingStep(String number, String title, String description) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _miniTag(number),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _note(description),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _captureNotice({required bool creator}) {
    final text = switch (room.captureStatus) {
      'live' =>
        creator
            ? 'Sound detected — sending to your room.'
            : 'Sound detected on the creator’s phone.',
      'silent' =>
        creator
            ? 'No app sound detected. Play audio in another app. If it is already playing, that app or content may block sharing. Test room speakers to check the connection.'
            : 'No app sound detected on the creator’s phone. Ask them to play audio or test the room speakers.',
      'noData' =>
        creator
            ? 'Audio capture is not responding. Stop sharing, then start it again and approve Android’s request.'
            : 'The creator’s audio capture is not responding. They need to restart sharing.',
      _ =>
        creator
            ? 'Waiting for app sound. Open your music or video app and press play.'
            : 'Waiting for the creator’s app sound.',
    };
    return _note(text, color: c.accentText);
  }

  void _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Your sound. Your people.'),
      content: const SingleChildScrollView(
        child: Text(
          '1. Choose your username once; it is saved on this phone. Tap your profile icon to change it later. Turn on the creator’s hotspot in Android settings, then connect every listener to that hotspot before joining.\n\n2. Name a room and share its six-digit code. Up to eight listeners can join. Everyone sees the room name and member list.\n\n3. Select Microphone, App audio, or Karaoke. Karaoke mixes the mic with captured music and adds Singer level, Backing music, and Your microphone controls. Singer reduction works best with stereo tracks and can affect instruments. Allow the requested permissions. The phone’s mic can play through its connected Bluetooth speaker. Select that speaker for media audio in Android settings.\n\n4. Keep Beatrazeem open on listeners and while using the microphone. App-audio creators can switch to the source app.\n\nOther-app capture needs Android 10+ and permission from the source app; some content cannot be shared.\n\nTo fine-tune a speaker: open Your speaker → Adjust speaker timing and follow the four steps. Stop sharing before adjusting. Delay faster phones to match the slowest phone at 0 ms. Reset returns to 0 ms.\n\nPlayback has a shared delay. Bluetooth and phone hardware can add more. Perfect synchronization and zero lag are not guaranteed.\n\nNames are shown to people in this nearby room. They are display names, not verified accounts. Audio is not uploaded or saved. Rooms use local discovery and unencrypted audio, so use trusted Wi-Fi. Guest networks may block discovery.',
          style: TextStyle(height: 1.5),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
