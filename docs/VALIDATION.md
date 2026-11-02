# Timing adjustment patch — 0.8.2 (build 15)

Flutter analysis passed with no issues. All 54 Flutter tests passed. Negative timing offsets are now clamped to zero; the adjustment UI adds delay only and is disabled during playback. Existing tests do not replace physical-device audio testing. No physical-phone test was performed for this patch.

# Validation — 2 November 2026, version 0.8.1 (build 14)

This update removes the Resync control and extra Live delay metrics, stabilizes app capture timestamps, interpolates small packet timing corrections, retains useful captured-audio bursts until delivery credit is available, and recovers automatically after output interruptions. The configured shared buffer remains 200 ms.

## Reproduced faults and fixes

- The added capture jitter regression failed against the previous code: consecutive 20 ms blocks were separated by 23 ms after one noisy timestamp. A backward observation could also collapse block spacing. Capture now uses a median-filtered, rate-limited sample clock and briefly waits for an initial hardware timestamp before emitting audio.
- Small positive packet timing corrections previously inserted silence; negative corrections skipped samples. Consecutive prequeued packets now interpolate continuously. A review found that retiming partially rendered packets could repeat or skip samples, so their mapping is frozen once rendering starts.
- Eight unacknowledged packets previously caused all later burst packets to be discarded, including packets still scheduled in the future. A bounded unsent queue now drains on acknowledgements, discards expired audio, and handles stream sequence restarts without granting duplicate delivery credit.
- Known output interruptions below 40 ms previously remained on the old sample cursor and recovered slowly. They now explicitly reanchor the output timeline; underruns are checked on every render cycle.

## Checks performed

- Flutter analysis: no issues.
- All 54 automated Flutter tests passed. New cases cover nine-frame capture bursts, bounded stalled listeners, expiry, stream resets, live delay refresh, and read-only delay controls. Existing profile, theme, Karaoke, discovery, clock, membership, and protocol checks remain covered.
- All 25 native timeline checks passed. Coverage includes noisy and backward capture timestamps, startup frame positions, positive/negative packet corrections, late successors, genuine missing packets, sample-derived delay, automatic interruption recovery, and capture-worker stalls. A two-minute simulation renders jittered capture plus room-clock corrections continuously; a separate ten-minute simulation checks independent speaker-clock rates.
- All 11 native Karaoke checks passed, including microphone continuity across 20 ms mixed packets.
- The updated Live delay preview was generated and visually reviewed. The displayed 204 ms is an illustrative test fixture, not a physical-device measurement. Small-screen widget checks passed at 360 pixels wide.
- Android ARM64 debug APK built successfully: package `com.beatrazeem.beatrazeem`, version `0.8.1`, version code `14`.
- APK signing verification passed with the existing certificate SHA-256 `56143b76408191b30c4ba1bab9f38a4c1a3972f6e8595865ac4d58681b572874`.

## Device verification still required

No physical multi-phone or acoustic latency test was performed. The user reported that the room chime was aligned while app audio differed; the fixes target the captured-audio path and identified continuity defects. Automated checks cannot confirm the reported symptom is gone on the user's phones.

Install 0.8.1 on every phone, connect listeners to the creator's hotspot, and recreate the room. Use built-in speakers with manual adjustments at 0 ms. Compare joined phones using the chime, then captured app audio for ten minutes. Read Live delay on each joined phone, verify that stale values disappear, and repeat after a route change. Test Karaoke with a real source app and speaker as well. An external acoustic recording is needed to measure audible alignment between phones.

## Measurement limits

Live delay maps captured samples to Android AudioTrack presentation timestamps. It depends on capture timestamps, room-clock estimation, the audio driver, and route reporting; it does not measure sound arrival or directly measure differences between phones. When fresh speaker timestamps are unavailable it shows Measuring… rather than zero. Drivers without capture timestamps use a sample-position estimate after bounded startup warmup; later timestamp corrections settle gradually. Bluetooth may add unreported latency. The creator's original source-app playback is not delayed or replaced by Beatrazeem.

Each listener has at most eight packets in flight plus ten unsent 20 ms packets (at most 200 ms unsent audio). Expired packets are dropped. A sufficiently slow connection can still cause audible gaps; the app does not replay an ever-growing backlog. Android 7+ supports joining and microphone mode; other-app capture and Karaoke require Android 10+ and source-app permission.

Android references: [AudioRecord timestamps](https://developer.android.com/reference/android/media/AudioRecord#getTimestamp(android.media.AudioTimestamp,%20int)), [AudioTrack timestamps and underruns](https://developer.android.com/reference/android/media/AudioTrack), and [playback capture](https://developer.android.com/media/platform/av-capture).
