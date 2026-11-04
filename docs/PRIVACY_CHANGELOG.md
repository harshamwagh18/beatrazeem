# Privacy update 0.9.3 — change map

Updated 4 November 2026, build 19. The first-opening screen now hides the data summary and the separate contact/deletion footer; Privacy opened after setup keeps them. Notice version `2026-11-04.1` is unchanged, so this presentation update does not ask existing users to agree again.

| Change | Where | Result |
|---|---|---|
| Hide footer on first opening | `lib/ui/privacy_screen.dart`, `test/privacy_ui_test.dart` | Hides the divider, “Data on this phone,” contact line and withdrawal button while showing the initial notice. Keeps them in the separately opened Privacy screen. |
| Remove age and acceptance checkboxes (retained from 0.9.2) | `lib/ui/privacy_screen.dart` | Removes “I am 9 years old or older” and both tick boxes. Shows plain text: “By continuing, I agree to the terms and conditions and privacy notice.” with a Continue button. |
| Record the actual action | `lib/core/privacy_store.dart`, Android `MainActivity.kt` | Records notice acceptance only after Continue and a successful save. Does not record age/adult confirmation; clears earlier age and guardian data when saving the new receipt. |
| Updated notice and migration | `lib/core/privacy_policy.dart`, `docs/PRIVACY_NOTICE.md` | Notice `2026-11-04.1` explains the simplified flow. Earlier receipts require Continue once; the saved username stays. |
| Preserve history | `docs/privacy-notices/2026-11-03.1.md`, `docs/PRIVACY_CHANGELOG_0.9.1.md` | Archives the previous notice and change record. |
| Regression checks | `test/privacy_ui_test.dart`, `test/privacy_store_test.dart`, shared test store | Checks that opening the page saves nothing, Continue saves acceptance without age claims, old receipts migrate, and failed saves/deletion stay blocked. |

Android `MainActivity.kt` is under `android/app/src/main/kotlin/com/beatrazeem/beatrazeem/`. The existing failed-write protection, contact line, local-data controls, room verification and audio timing implementation remain.

See [Validation](VALIDATION.md) for completed checks and [Privacy operations](PRIVACY_OPERATIONS.md) for the operator's remaining obligations. No new physical audio or legal-compliance claim is made by this UI update.
