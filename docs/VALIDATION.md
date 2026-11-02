# Validation — 3 November 2026, version 0.9.0 (build 16)

This release adds privacy onboarding, versioned local consent, local withdrawal/erasure, guardian approval verification, privacy request drafts, backup exclusions, and authenticated encrypted rooms. See PRIVACY_CHANGELOG.md for source locations and PRIVACY_OPERATIONS.md for operational obligations and unresolved legal questions.

## Checks completed

- Flutter static analysis: no issues.
- Full Flutter suite: 84 tests passed after secure transport, consent UI, storage and guardian validation integration. Subsequently added two peer-verification UI tests and one guardian-email fallback test; all 11 affected privacy/peer UI tests passed after the final fallback change. This covers 87 distinct app checks across the full and targeted runs.
- Consent tests cover unchecked affirmative choices, existing-profile gating, invalid/stored guardian approvals, failed consent saves, active-room shutdown on withdrawal, failed erasure staying blocked, and explicit email/copy fallback.
- Guardian validation checks signatures, phone reference, notice version, expiry, future issue time, excessive lifetime, malformed payloads and tampering. The operator tool's five Python tests passed. These checks verify signed decisions, not the identity or authority of real guardians.
- Transport tests cover approval before personal-data exchange, encrypted payload inspection, decline/default denial, tampering/replay/plaintext rejection, source resets, queue bounds, room discovery, authenticated clock messages, session revocation and UDP flood recovery.
- Four UI preview tests passed; the new Privacy screen was rendered and visually inspected. Timing-preview numbers remain illustrative fixtures.
- Android debug APK built successfully; application com.beatrazeem.beatrazeem, version0.9.0, versionCode16, minimumAndroid24 (Android7), target35. App-audio capture and Karaoke still require Android10+.
- APK signature verified with the existing signing certificate SHA-256 56143b76408191b30c4ba1bab9f38a4c1a3972f6e8595865ac4d58681b572874.
- Operator signing key is outside the application/source repository. Only its public verification key is included in the app.

## Limits and remaining verification

No real-device multi-phone test, acoustic synchronization measurement, manufacturer backup/transfer test, live guardian identity check, real mailbox request handling, or independent cryptographic audit was performed. Tests use synthetic media, loopback networking and mocked platform calls where appropriate. The pairing protocol uses established library primitives, but the protocol itself still needs independent security review. Users must actually compare both phones' security codes.

Local discovery and connection/traffic metadata remain visible. The Android cleartext-carrier flag remains necessary for local discovery and the WebSocket carrier; personal payloads are encrypted inside that carrier. Old clients are rejected rather than receiving plaintext fallback.

Guardian approvals enforce an operator decision after manual verification; no external identity-verification service is connected. Offline approvals cannot be remotely revoked immediately, and device clock manipulation can affect expiry. The adult route uses self-declaration. These limitations, legal-role determination, final Rules6/8 retention applicability, mailbox staffing, rights/nomination handling and effective breach-notification delivery remain operator/release requirements. This is a development build with added privacy/security controls, not a certification that all laws are satisfied.

Install0.9.0 on every test phone, accept the notice (or use a properly issued guardian approval), recreate rooms, compare security codes, and verify microphone/app audio/Karaoke with built-in and Bluetooth speakers. Test withdrawal while sharing, restart after deletion, permission revocation, declined device verification, approval expiry, phone-clock changes and backup/restore behavior. Retain evidence before public release.
