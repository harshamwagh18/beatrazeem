# Beatrazeem — Android app, v0.9.4 test release

Beatrazeem creates nearby listening rooms with a **6-digit code**. There is no website, account, upload form, or cloud audio storage in this app.

## Security update — 0.9.4

Local room lookup now limits repeated code guesses, uses temporary backoff and respects Retry-After. Existing six-digit joining and peer approval remain. New joins may temporarily wait after repeated incorrect codes or heavy traffic. See [audit findings, fixes and compatibility decisions](docs/SECURITY_AUDIT_REMEDIATION.md).

## Use it

1. Install Beatrazeem 0.9.4 on every device. Read the terms and privacy notice, then tap Continue. The agreement is plain text with no age prompt or checkbox. Turn on the creator phone’s hotspot in Android settings and connect every listener to that hotspot. Enter a username once. It is saved on that phone; later launches open the home screen directly.
2. On the creator, select **Host**, enter a room name, and tap **Create a room**. Share the six digits shown on screen.
3. On listeners, select **Join**, enter those digits, and tap **Join room**. Compare the separate security code on the creator and listener phones, then approve on both. The room name and live member list appear on every updated phone.
4. The creator selects **Microphone**, **App audio**, or **Karaoke**, then starts sharing.
5. Connect each device to a speaker using the operating system's Bluetooth, cable, or audio-output settings.
6. Use **Test room speakers** and **Adjust speaker timing** to compare outputs. The test stops an active sharing session; start sharing again afterward. Listener apps must remain open.

There can be one creator and up to eight listeners. Rooms end when the creator leaves or the app process stops. Guest Wi-Fi, AP isolation, VPNs, and some hotspots may block nearby discovery.

## Simpler first-opening screen — 0.9.4

- The initial notice screen ends with the agreement, Continue and Decline controls. The data summary, contact footer and local-deletion button appear only when opening Privacy separately.
- **Privacy & your data**, available from the shield icon, keeps the full notice, local data summary and withdrawal with local deletion.
- The guardian-approval controls and privacy-request/complaint form have been removed. A selectable line says **“If you have any queries, contact gamelauncer223@gmail.com.”** The responsible operator remains **gamelauncher**. Users send any email themselves; the app does not submit a request.
- Onboarding shows “By continuing, I agree to the terms and conditions and privacy notice.” followed by Continue. There are no checkboxes or age-confirmation prompts. A successful Continue records acceptance of this notice, without making an age or adult claim.
- Notice **2026-11-04.1** replaces the previous notice. Existing users must accept it again before entering rooms; their saved username stays available. Accepting the new notice removes obsolete age confirmation and guardian approval/request data. Old age, adult or guardian receipts do not automatically grant access under the changed notice.
- Withdrawing stops input/output, closes the room and erases the local profile and privacy records. A failed erase is reported with retry/Android clear-storage instructions. Configured cloud/device backups exclude app data.
- Android capture now explicitly checks revoked audio permission and handles optional sharing-notification permission. Newer navigation-bar styling is limited to supported Android versions. Failed consent writes remain blocked even after reopening the Activity.
- Room encryption and connection verification remain in place. Compare matching security codes on both phones before approving a connection. The six-digit room code remains the joining method; protocol v3 has no plaintext fallback.

**This development build is not a legal-compliance certificate or production approval.** This flow does not verify age or parental consent. The operator still needs to resolve the child-use requirements, handle requests sent to the contact address, determine applicable retention, and establish effective breach-notification delivery. Physical-device and independent security reviews remain necessary. See [change locations](docs/PRIVACY_CHANGELOG.md), [operator procedures](docs/PRIVACY_OPERATIONS.md), [current notice](docs/PRIVACY_NOTICE.md), [previous notice](docs/privacy-notices/2026-11-03.1.md), and [validation](docs/VALIDATION.md).

The distributed APK uses Flutter release mode for phone testing, with the existing development signing certificate so it can update the previous build. It is not a production signing setup.

## New in 0.8.1: Continuous app audio and a simpler delay display

- **Live delay** now shows only estimated playback delay in milliseconds. The Resync button and extra metrics are removed. Timing continues to adjust automatically; the existing **Adjust speaker timing** guide remains available.
- App-audio and Karaoke capture now use a continuous, filtered sample clock. Recorder timestamp jitter no longer moves every audio block abruptly. Capture briefly waits for the first hardware timestamp, with a bounded fallback for drivers that do not provide one.
- Small timing corrections between queued, consecutive packets are interpolated smoothly instead of inserting silence or skipping samples. Already-rendered samples are never retimed. Missing packets and large gaps remain gaps rather than replaying old sound.
- Bursts of captured audio now wait in a bounded per-listener queue for delivery credit. Previously, a ninth unacknowledged packet was discarded even when its playback time was still in the future. Expired audio is discarded so a stalled connection cannot accumulate an ever-growing delay.
- Output interruptions and route changes reanchor playback automatically, including short interruptions that previously took seconds to catch up.
- The shared target buffer remains **200 ms**, using **20 ms packets**. This update fixes continuity and timing behavior without reducing the buffer further.
- Install **0.9.4 on every phone** and recreate the room. Saved profiles remain intact during a normal update.

Live delay is estimated from capture and speaker timestamps, not an acoustic measurement. Unavailable or stale timing shows **Measuring…**; Bluetooth may add unreported delay. The delay preview uses an illustrative value, not a measured phone result.

## Creator hotspot support (added in 0.7.0)

- The creator can provide the hotspot. Listeners look up the room directly through their Wi-Fi gateway using the six-digit code, so hotspot joining no longer depends on multicast discovery. Normal shared-Wi-Fi discovery remains available as a fallback.
- Listener networking is bound to the selected Wi-Fi network while joining and listening, including a hotspot without internet access. The binding and Wi-Fi performance lock are released on leaving, failure, or disconnection. The creator does not need to connect to a listener's hotspot.
- Clock checks use a separate UDP path every 250 ms so queued audio does not delay them. Networks that block authenticated UDP use the encrypted TCP clock fallback. Older app versions are rejected.
- Speaker timestamps are checked every second once established, with rate estimates fitted over a longer window. Playback follows the measured speaker sample rate; expired timestamps fall back to an estimate and route changes reset the measurement.
- App-audio and Karaoke capture use Android recorder frame timestamps when available, with a continuous sample-position fallback. Delayed reads retain their original age and expired audio is dropped instead of building up lag.
- Each updated listener can have at most eight unacknowledged packets plus ten unsent 20 ms packets (at most 200 ms of unsent audio). Acknowledgements release delivery credit; expired packets and excess oldest unsent packets are discarded. Each listener is handled independently.

Start with **Test room speakers**, using the phones' built-in speakers and 0 ms manual correction. Compare joined phones with one another. The creator's original YouTube/Spotify playback is outside Beatrazeem's playback buffer and remains earlier than the shared audio. The app cannot delay or replace that source playback. These changes passed software tests; physical hotspot compatibility and audible alignment still need device testing.

Android 7+ can join rooms and use microphone mode. Capturing other apps and Karaoke require Android 10+. This build does not support every historical Android version.

## Saved profile (added in 0.6.1)

- Enter your username once. It is stored in the app's private preferences and restored when Beatrazeem opens again, including after a normal app update.
- Tap your initials in the top bar to open **Profile → Change username**. Edit the name and tap **Save changes**. **Cancel** keeps your current name.
- You can change your name on the home screen or while in a room. Updated creators and listeners receive the new member name without leaving, rejoining, or stopping audio. Install this update on every phone for live name changes.
- Names are still display names, not accounts. No password or sign-in is needed. Clearing the app's data removes the saved profile; a new installation may ask again unless Android restores its data.
- Earlier versions did not save usernames, so enter your name once after installing this update. Saving errors offer a retry; the app does not report success until the local save finishes.

## Karaoke (added in 0.6.0)

1. On the creator phone, select **Karaoke → Start Karaoke**. Allow microphone access and approve Android's audio-sharing request. Android 10 or newer is required on the creator.
2. Open a music app that allows playback capture and play a song. Sing into the creator phone's microphone. Beatrazeem combines both inputs into one stream for the room.
3. Use **Singer level** to reduce or emphasize the song's centered vocal band: 0–150%, with 100% as the original level. This is an approximate stereo vocal-reduction effect, not separate singer audio or AI voice isolation. It works best with stereo tracks whose vocals are centered; instruments may change too, and some vocals will remain.
4. Adjust **Backing music** (0–100%) and **Your microphone** (0–200%) independently. **Reset mix** restores singer 100%, backing music 70%, and microphone 100%.
5. **Karaoke mix on this device** starts enabled and follows Android's selected media speaker, including Bluetooth. The source app's original playback can still be heard on the creator; the singer control changes only Beatrazeem's processed mix. To hear only that mix, switch creator monitoring off and use joined phones as speakers.
6. Return to Beatrazeem and tap **Stop sharing** when finished. The ongoing Android notification identifies that the Karaoke microphone is on while you use another app.

Keep the microphone away from speakers to reduce feedback. The room buffer and Bluetooth introduce an audible monitoring delay, so this is not an instant stage microphone. Source apps that block playback capture cannot supply the backing track. The filter and controls passed automated checks; simultaneous capture, microphone routing, and sound quality still need testing on physical phones.

## Speaker timing guide (retained)

- In each room, open **Your speaker → Adjust speaker timing** for a four-step guide, a creator chime shortcut, Earlier/Later 10 ms buttons, and Reset to 0 ms. Adjustments apply only to this phone.

## Audio timing update (retained)

- Continuous Android AudioTrack playback replaces separate per-block sounds. Hardware presentation timestamps are used when available; unsupported routes use a playback-head fallback.
- Capture-time deadlines prevent main-thread callback stalls from creating growing playback lag. Expired captured blocks are dropped.
- Four-timestamp clock exchanges account for creator processing delays and smoothly track clock drift. Joining waits for usable timing.
- The test chime plays on the creator even when app-audio monitoring is off, and its buffered ending can finish.
- The creator’s original source app remains earlier than captured playback. For aligned app-audio listening, use joined phones as speakers and keep creator monitoring off to avoid echo. Android playback capture does not delay the source app: https://developer.android.com/media/platform/av-capture

## Retained design

- Dark mode now uses the same bright-purple primary and pale-purple secondary accents as light mode. Filled buttons and the room-code card use white foregrounds in both themes. Dark backgrounds and readable light text are retained.

- Redesigned welcome, Host/Join hub, and room interfaces with a stronger visual hierarchy and animated sound artwork.
- Complete light and dark themes using the requested purple palette. The app starts with the phone's theme; the theme control changes it for the current app session.
- Animated interface transitions and sound visuals that respect the phone's reduced-motion preference.
- Native Android launch backgrounds follow the phone's light or dark theme, with an updated purple launcher icon.

| UI element | Light theme | Dark theme |
| --- | --- | --- |
| Background | `#FFFFFF` | `#121216` |
| Secondary background | `#F5F5F7` | `#1E1E24` |
| Primary accent | `#7C3AED` | `#7C3AED` |
| Secondary accent | `#DDD6FE` | `#DDD6FE` |
| Primary text | `#18181B` | `#F4F4F5` |
| Secondary text | `#71717A` | `#A1A1AA` |

The room identity features from 0.2.0 are retained:

- A username chosen once before hosting or joining, saved on the phone, and editable from Profile at any time. No account or password is created.
- A required room name for creators, displayed to everyone in the room.
- A live **In this room** member list with initials, creator labels, and a **(you)** indicator. Joining, leaving, and manually rejoining update the list.

Usernames are limited to 24 characters and room names to 36. Usernames are saved display names, not verified accounts, and are shared with the connected room. Room names last for the room session. Duplicate names are allowed; each connection has its own identity. Update all phones to 0.9.4 for creator-hotspot discovery, bounded audio queues, saved profiles, and live name changes. Older versions must update before joining encrypted rooms.

Room codes, host microphone routing, and the Android output scheduling and room-clock improvements from 0.5.0 are retained. Automatic reconnection is not included; use Join again after a connection is lost.

## What is implemented

- Native Android app built with Flutter.
- Six-digit room generation and code-only joining through direct hotspot-gateway lookup, with Bonjour/Android NSD for shared-Wi-Fi discovery.
- Live microphone capture and playback through the device's selected audio route.
- Microphone playback on the host's selected speaker starts enabled, including a Bluetooth speaker selected for media audio. It can be switched off independently of room listeners.
- Android 10+ audio-playback capture with the system consent dialog and an ongoing foreground-service notification.
- Karaoke: simultaneous stereo app-audio capture and phone microphone capture, vocal-band reduction/emphasis, separate music and microphone levels, and a combined mono room stream.
- Multiple listeners, clock offset measurement, timestamped PCM blocks, capture-based deadlines (a 200 ms target from the first captured sample), volume/mute, and per-device timing compensation.
- Test chime, permission errors, room teardown, and connection-loss messages.
- App-audio status on both creator and listeners: waiting for sound, sound detected, silent input, or stalled capture. Silence does not prove that an app blocks capture.

## Use the host phone as a Bluetooth microphone (0.1.2)

1. Pair the speaker with the host phone in Android settings and select it for **media audio**.
2. In Beatrazeem, create a room, choose **Microphone**, and tap **Turn on microphone**. Allow microphone access.
3. Speak into the phone. **Play mic on host speaker** starts enabled. No other listener needs to join for the host's speaker to work. Other room listeners receive the same microphone stream.
4. Leave Beatrazeem open. Check that its output is unmuted and raise Android's media volume if needed. Keep the phone away from the speaker to avoid feedback.

The app prefers the phone's built-in microphone and leaves Bluetooth on Android's selected media route. It does not activate a Bluetooth headset-call connection or force the phone's loudspeaker. Actual routing depends on the phone. Bluetooth adds delay on top of the room playback buffer; this is not an instant PA microphone. The user reported the 0.1.2 app working. This redesign retains that audio path; new device and speaker combinations still need hardware testing.

## App-audio update (0.1.1, retained)

Android 14 and newer, including Android 16, now request device-wide sharing consent for switching between audio apps. Beatrazeem still captures only audio: it creates no video display and does not record your screen. The app also checks that Android starts the recorder and reports whether captured sound is present. These changes are not yet verified on a physical Android 16 phone.

If connected devices are silent, follow [the app-audio checks](docs/APP_AUDIO_TROUBLESHOOTING.md). Install the latest update on every device so listeners can show the new status messages.

## Important limits

This is an early development build, not a production release. Building source is not evidence of real-device compatibility. Check `docs/VALIDATION.md` for the actual checks performed.

**Other-app audio is implemented only for Android 10+.** The source app must allow capture. Spotify, YouTube, DRM-protected content, and arbitrary apps are not guaranteed to be capturable. No capture protections are bypassed.

**Zero lag is impossible to promise.** Listeners use a shared buffer to absorb network jitter. Software scheduling, audio hardware, and Bluetooth add latency. The creator's original app audio is not delayed by Beatrazeem and can be heard earlier than receivers. A video on the creator may not lip-sync with the remote audio. Physical device synchronization has not been measured here.

**Local-network rooms only.** A six-digit code does not connect devices over the internet. Network discovery exposes the room code locally. Names, room information and audio travel inside authenticated encrypted messages after mutual security-code verification. Discovery and traffic metadata remain visible on the local network. The code identifies a nearby room; it is not a security credential. There is no recording or file upload feature.

**Keep listener apps open.** Mobile background listening is not configured. Android app-audio sharing and Karaoke use a foreground service while another app plays. Karaoke keeps the microphone active until sharing stops; microphone-only mode pauses when Beatrazeem is backgrounded. Output routing follows the system. Bluetooth behavior depends on the phone and speaker.

## Build

Install Flutter 3.47.7 (Dart 3.13.5) or a compatible version and the Android SDK with Java 17, then:

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Android:

```sh
flutter build apk --release --target-platform android-arm64
```

A debug APK is a testing package, not a Play Store release. Release signing must use your own signing key. Do not ship with the template debug signing configuration.

The included CI workflow checks and builds the Android app. No CI run has been triggered by this delivery.

## Architecture

`lib/core/discovery.dart`: direct hotspot lookup and optional native multicast discovery.

`lib/core/direct_discovery.dart`: a code-checked room lookup endpoint on local TCP port 45873.

`android/.../LocalNetwork.kt`: reads actual Wi-Fi routes/DHCP gateway, binds listener sockets to Wi-Fi, and manages the Wi-Fi performance lock.

`lib/core/clock_link.dart`: independent UDP clock exchanges on the room's port, with TCP timing fallback.

`lib/core/transport.dart`: room admission, local WebSocket fanout, bounded acknowledged audio delivery, clock measurements, state and teardown.

`lib/core/protocol.dart`: bounded binary audio frames, six-digit validation, clock estimator, PCM framing.

`lib/core/capture_health.dart`: signal, silence, and stalled-input detection without guessing a source app's capture policy.

`lib/audio/audio_engine.dart`: native microphone capture, continuous microphone sample times, Android clock calibration, timing reports, and AudioTrack output; SoLoud is retained only as the non-Android fallback.

`lib/audio/audio_timing.dart`: validates fresh native playback-delay estimates and rejects stale or invalid measurements.

`lib/ui/delay_panel.dart`: read-only Live delay with fresh playback estimates and unavailable states.

`android/.../CaptureService.kt`: consent-based Android playback capture, concurrent Karaoke microphone capture, foreground notification, cleanup on revocation.

`android/.../CaptureSampleClock.kt`: filtered, rate-limited recorder frame-to-time mapping, preserving capture age through worker stalls.

`android/.../PcmTimeline.kt`: bounded PCM timeline, continuous interpolation for small packet timing corrections, and measured speaker-clock tracking.

`android/.../KaraokeMixer.kt`: stereo center-band reduction/emphasis, timestamped microphone mixing, smoothed independent gains, and peak limiting. This is not source separation.

`lib/main.dart`: profile, home, room UI, and audio controls.

`lib/ui/design.dart`: light/dark purple themes, avatars, animated native sound artwork, and responsive waveform.

`lib/core/room_member.dart`: member identities and bounded display-name validation.

`lib/core/profile_store.dart`: validated username persistence through the Android profile channel.

`lib/ui/profile_dialog.dart`: editable profile, validation, cancel, save, and retry feedback.

`android/.../MainActivity.kt`: the profile channel reads and commits private Android preferences on a background executor; the UI acknowledges a save only after the write completes.

PCM is 48 kHz, mono, 16-bit (about 96 KB/s per listener before transport overhead). Audio uses 20 ms network blocks and continuous native Android output in 10 ms render blocks. This favors a simple inspectable prototype; a production release should use an efficient codec, an independent audit of encrypted transport, wider device coverage for output timestamps and drift correction, background audio, reconnection, and multi-device acoustic calibration.

## Timing adjustment update — 0.8.2

Timing adjustment now adds 0–500 ms of delay only. Negative adjustments could consume the entire arrival buffer and cause missing audio. Keep the slowest joined phone at 0 ms and delay faster phones to match it. Stop sharing before changing timing, then replay the chime. Controls are locked while audio plays to avoid discontinuities from changing packet deadlines mid-song. This does not eliminate network dropouts or align the creator's original source-app playback with captured audio.
