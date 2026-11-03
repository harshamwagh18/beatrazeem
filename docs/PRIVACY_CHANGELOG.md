# Privacy update 0.9.1 — change map

Updated 4 November 2026 for version 0.9.1 (build 17). This update simplifies the privacy screen and changes the age declaration to 9 or older at the user's request. It removes the previous verified-guardian onboarding route. It is not a legal-compliance certificate. Final build and test results are recorded in [Validation](VALIDATION.md).

## What changed and where

| Change | Location | Result |
|---|---|---|
| Remove guardian approval controls | `lib/ui/privacy_screen.dart`, `lib/main.dart` | Removes guardian selection, verification-request and approval-entry controls. The current onboarding flow does not accept guardian approvals. |
| Minimum age 9 | `lib/ui/privacy_screen.dart`, `lib/core/privacy_store.dart`, Android `MainActivity.kt` | Requires an unchecked minimum-age confirmation and a separate notice agreement. Stores minimum-age confirmation, not a false adult or verified-parent decision. No birth date is collected. |
| Replace request/complaint controls | `lib/ui/privacy_screen.dart` | Removes request categories, email-draft and copy-request buttons. Displays selectable text: “If you have any queries, contact gamelauncer223@gmail.com.” |
| Updated contact and notice | `lib/core/privacy_policy.dart`, `docs/PRIVACY_NOTICE.md` | Uses the newly supplied contact address and notice version `2026-11-03.1`; explains the changed age and contact flows. The operator name remains gamelauncher. |
| Reconfirm after updating | `lib/main.dart`, `lib/core/privacy_store.dart`, Android `MainActivity.kt` | Old adult/guardian receipts cannot silently accept the new notice. The username is retained. Accepting the new notice removes obsolete guardian approval/request data. |
| Failed-save protection | Android `MainActivity.kt`, `PrivacyWriteGuard.kt`, `PrivacyWriteGuardHarness.kt` | Prevents a failed disk save from granting access through Android's already-updated memory cache after Activity recreation. Eight native checks cover failures, retry, deletion and concurrent reads. |
| Capture permission recovery | Android `CaptureService.kt` | Rechecks audio permission before capture and reports revoked permission while releasing partially created resources. |
| Android compatibility | Android `MainActivity.kt`, `AndroidManifest.xml`, `res/values*/styles.xml` | Guards app-audio service startup by Android version, scopes newer navigation-bar styles to Android 8.1+, and requests optional sharing notifications on Android 13+. Declining notifications does not block sharing. Pending sharing requests are cancelled when capture is stopped. |
| Preserve previous notice | `docs/privacy-notices/2026-11-02.1.md` | Keeps the exact previous notice, including the old contact and guardian process, as historical documentation only. |
| Updated tests and release information | `test/privacy_ui_test.dart`, `test/privacy_store_test.dart`, shared test setup, `README.md`, `docs/VALIDATION.md` | Covers the new gate, migration and removed controls while retaining withdrawal, storage-failure and audio/network checks. Refer to validation for completed runs and limitations. |

Android `MainActivity.kt` is under `android/app/src/main/kotlin/com/beatrazeem/beatrazeem/`.

## Controls retained

The local data summary, username correction in Profile, withdrawal with local deletion, encrypted room connections, manual comparison of security codes, authenticated clock messages and configured Android backup exclusions remain. Room audio is still temporarily buffered rather than saved as recordings. Clearing this phone cannot delete independently held recipient recordings or operator correspondence.

The historical guardian parser/signing utility and related tests may remain in the source for compatibility/history. They are not a guardian-enrolment service in 0.9.1, and their presence must not be presented as a verified parental-consent feature for this release. Do not issue new approvals expecting this version's onboarding screen to import them.

## Verification and limits

The native audio checks have been rerun against the current Kotlin sources: 25 timing checks and 11 Karaoke checks passed, including simulated speaker-clock drift and uneven capture timing. No new audio defect was reproduced in those checks and this UI update does not change the audio scheduling design. Full app checks, Android build and signing evidence are recorded in [Validation](VALIDATION.md).

Automated tests cannot establish lag-free acoustic output on physical phones or Bluetooth speakers. The creator's original app playback remains outside Beatrazeem's shared playback buffer. Real-device tests remain necessary.

## Remaining release requirements

1. Confirm ownership, delivery and staffing of the newly supplied contact address. Removing the request form does not answer requests received by email.
2. Resolve requirements for users aged 9–17 and people needing lawful-guardian consent before claiming compliance. A minimum-age checkbox is not verified parental or guardian consent.
3. Document applicable retention and erasure decisions for app processing and operator-held records.
4. Establish effective request, nomination, grievance and incident-notification procedures.
5. Complete physical-device and independent security review for the distributed build.

See [Privacy operations](PRIVACY_OPERATIONS.md) for procedures and the dated legal review retained from the preceding release.
