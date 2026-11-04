# Validation — 4 November 2026, version 0.9.2 (build 18)

This release replaces the age and agreement checkboxes with a plain terms-and-conditions statement and Continue. Continuing records notice acceptance without claiming age confirmation. Earlier receipts migrate after Continue while preserving the saved username.

## Checks completed for this update

- **Full Flutter suite: 90 tests passed.** Coverage includes opening the notice without saving consent, Continue with no checkboxes, no new age/adult claim, migration from the previous age/adult/guardian receipts, save failures, withdrawal/deletion, profiles, room discovery, encrypted transport, clock timing and audio/microphone/Karaoke behavior. Platform calls are mocked where appropriate.
- **Flutter static analysis: no issues.**
- **Android lint: 0 errors, 11 existing warnings.** Warnings concern target SDK, unused/redundant resources and optional Kotlin style suggestions; no suppression or baseline was added.
- **Optimized ARM64 Android APK built successfully**, version 0.9.2 / 18, package com.beatrazeem.beatrazeem, minimum API 24 and target API 35. App-audio capture and Karaoke require Android 10+.
- **APK signature verified** with the previous development certificate SHA-256 `56143b76408191b30c4ba1bab9f38a4c1a3972f6e8595865ac4d58681b572874`, allowing normal test-build updates. Release mode still uses development signing.
- The privacy screen preview was rendered and visually inspected. UI and migration behavior were covered by the automated suite.

The preceding 0.9.1 update passed 25 native audio-timing checks, 11 native Karaoke checks, 8 native failed-write checks and 5 legacy operator-tool checks. Those unchanged helpers were not rerun for this UI/storage-schema update; Android compilation/lint checks the changed native receipt handling. The prior change record is [archived here](PRIVACY_CHANGELOG_0.9.1.md).

## Limits

No physical-phone upgrade, notification/permission interaction, acoustic synchronization, on-device disk-failure, OEM backup or independent security test was performed. Flutter platform tests use mocks, and local software tests do not establish zero audible lag. Audio scheduling was not changed by this release.

The notice still describes an intended audience aged 9+, but the interface does not ask for or verify age. Continuing is not verified parental consent. See [Privacy operations](PRIVACY_OPERATIONS.md) for the existing operator/release requirements. This UI change makes no new legal-compliance claim.
