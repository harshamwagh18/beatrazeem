# Validation — 4 November 2026, version 0.9.3 (build 19)

This presentation update hides “Data on this phone” and the separate contact/deletion footer on the first-opening notice screen. Opening Privacy separately keeps those controls. Notice version `2026-11-04.1` is unchanged; existing acceptance and saved usernames remain valid.

## Checks completed for this update

- **15 targeted privacy and UI tests passed.** These cover first-opening footer visibility, the retained Privacy controls and data-copy action, Continue and saved consent, upgrade cases, failed saves, active-room withdrawal/deletion and broader UI behavior.
- **Flutter static analysis: no issues.**
- **Optimized ARM64 Android APK built successfully**, version 0.9.3 / 19, package com.beatrazeem.beatrazeem, minimum API 24 and target API 35. App-audio capture and Karaoke require Android 10+.
- **APK signature verified** with the previous development certificate SHA-256 `56143b76408191b30c4ba1bab9f38a4c1a3972f6e8595865ac4d58681b572874`, allowing normal test-build updates. Release mode still uses development signing.

The full 90-test Flutter suite and Android lint (0 errors, 11 warnings) passed for 0.9.2. Earlier native timing, Karaoke and failed-write checks passed for 0.9.1. Those unchanged audio/storage components were not retested for this conditional UI change. No new physical-phone or acoustic synchronization claim is made.

The terms and notice still describe an intended audience aged 9+, while the interface does not ask for or verify age. See [Privacy operations](PRIVACY_OPERATIONS.md) for the existing release requirements.
