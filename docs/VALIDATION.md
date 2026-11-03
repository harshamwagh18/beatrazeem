# Validation — 4 November 2026, version 0.9.1 (build 17)

This update removes guardian approval and privacy-request controls, displays the supplied contact line, and uses a self-declared minimum age of 9. It also fixes Android compatibility/permission checks and guards failed consent writes. See [change locations](PRIVACY_CHANGELOG.md).

## Completed checks

- **Full Flutter suite: 88 tests passed.** Includes age/notice gating, upgrade from adult and guardian receipts, saved-profile preservation, absent controls and exact contact text, failed saves/deletion, room discovery, encrypted transport, clock synchronization, stalled queues, capture timelines, microphone, Karaoke and UI behavior. Platform calls are mocked where appropriate.
- **Flutter static analysis: no issues.**
- **Native audio: 25 timing checks and 11 Karaoke checks passed**, using freshly compiled Kotlin sources. Timing cases include simulated ten-minute speaker-clock drift, two-minute jittered continuous capture/output, stale-packet dropping, buffer bounds and interruption recovery. No audio scheduling algorithm was changed for this release.
- **Native privacy persistence: 8 checks passed.** These model Android's memory-before-disk preference writes, including failure/exception after memory mutation, Activity recreation, concurrent reads, explicit retry and deletion recovery. The process-wide guard keeps unconfirmed consent unreadable. These are host-JVM checks, not on-device storage instrumentation.
- **Legacy operator utility: 5 Python tests passed.** The old signing utility remains historical source; it does not provide child enrolment in this version.
- **Android lint: 0 errors, 11 warnings.** Fixed all eight reported errors: capture permission checks, version-guarded service startup, version-qualified navigation-bar styling, and notification permission declaration. Remaining warnings concern target SDK 35 versus 36, redundant/unused resources and optional Kotlin style suggestions. No lint baseline or error suppression was added.
- **UI preview:** rendered the simplified privacy screen and inspected it visually. The existing automated UI previews passed in the full suite. Any displayed timing-preview numbers are illustrative fixtures.
- **Android packaging:** debug build compiled during integration; the delivered APK is the final optimized Flutter **release-mode** build for **ARM64**, version **0.9.1 / 17**, package **com.beatrazeem.beatrazeem**, minimum Android 7 (API 24), target API 35. App-audio capture/Karaoke require Android 10+. Release compilation also runs Android's release-vital checks.
- **APK signature verified** with the same development certificate as previous builds: SHA-256 `56143b76408191b30c4ba1bab9f38a4c1a3972f6e8595865ac4d58681b572874`. This permits test-build updates; it is not a production signing setup.

## Actual fixes from validation

`CaptureService.kt` explicitly rechecks audio permission before starting capture and handles revocation with cleanup. `MainActivity.kt` guards projection/service APIs by Android version, supports optional sharing notifications, cancels outstanding permission requests on stop, and uses `PrivacyWriteGuard` for consent writes/reads. Notification refusal does not prevent foreground sharing; see [Android's documented behavior](https://developer.android.com/develop/ui/compose/notifications/notification-permission). New `values-v27` and `values-night-v27` styles restrict newer navigation-bar attributes to supported devices.

## Limits and phone testing still needed

No physical multi-phone/acoustic test, actual permission-dialog test, OEM backup/transfer test, on-device disk-failure test or independent security review was performed. Device enumeration could not complete because this environment could not access Android's device configuration directory; this does not establish whether a phone was attached. Existing tests use simulated media, host networking and platform mocks. Notification grant/deny/cancel and permissions revoked during sharing still require verification on phones.

Passing these tests does **not** establish zero lag. The room deliberately buffers audio for synchronized scheduling, Bluetooth may add delay, and the creator's original YouTube/Spotify playback cannot be moved into Beatrazeem's shared timeline. Compare joined phones with each other and use the speaker timing guide. No new timing fault was reproduced in the software checks.

Install this APK on each compatible test phone, accept the revised notice and retain the saved username. Connect listeners to the creator hotspot, create/join with the six-digit room code, compare security codes, then exercise the test chime, app audio, microphone and Karaoke. Check both speaker routes, longer playback, interruptions, permission denial, withdrawal while sharing and restart after deletion. Record measured results before claiming audible synchronization across devices.

The 9+ checkbox is a self-declaration, **not verified parental consent**. This build does not claim full legal compliance; the operator's child-use, request-handling, retention and incident-response obligations remain unresolved as described in [Privacy operations](PRIVACY_OPERATIONS.md). A failed on-disk deletion cannot be promised durable across full process restart; retry deletion or clear app storage as instructed.
