# Privacy update 0.9.0 - change map

Updated 3 November 2026 for the DPDP readiness update. This map identifies the implementation work and the operational requirements that remain. It is not a legal-compliance certificate. Final app build and integration results belong in `VALIDATION.md`.

## App changes and their locations

| Change | Location | Effect and limits |
|---|---|---|
| Operator identity and standalone notice | `lib/core/privacy_policy.dart` | Identifies gamelauncher and gamelauncher223@gmail.com; explains data, purposes, recipients, storage, choice, rights and complaints. Mailbox operation must be established by the operator. |
| Privacy onboarding and later review | `lib/ui/privacy_screen.dart`, `lib/main.dart` | Presents notice before profile/room processing, requires affirmative choice and offers later data/rights access. Integration must fail closed on missing or expired approval. |
| Local consent receipt and deletion | `lib/core/privacy_store.dart`, Android `MainActivity.kt` | Saves notice version, local acceptance time and eligibility/guardian decision; supports removal of local profile and privacy data. This does not delete independently held recipient recordings or operator correspondence. |
| Existing profile handling | `lib/core/profile_store.dart`, `lib/main.dart` | Upgraded users must pass current consent/eligibility checks before resuming room use; profile correction remains available. |
| Guardian approval verification | `lib/core/guardian_approval.dart` | Checks an Ed25519 signature, device request ID, notice version, issue time and expiry. Signature validation authenticates the operator decision; it does not independently verify the guardian's identity, adulthood, authority or consent. |
| Operator approval issuance | `tools/guardian_approval.py` | Signs only after explicit confirmations of the four required operator checks. Default approval lasts 30 days, with a maximum of 90 days. Private keys remain outside the app/source repository. |
| Protection against backup restoration | Android `AndroidManifest.xml` and backup exclusion XML | Excludes app privacy/profile data from configured backup/transfer mechanisms; actual manufacturer behavior needs device testing. |
| Encrypted room connection | `lib/core/secure_room_socket.dart`, `lib/core/transport.dart` and `lib/ui/peer_verification_dialog.dart` | Protects room messages after authenticated connection verification. Room discovery and traffic metadata can remain visible. All peers need the compatible app version. |
| Privacy requests and complaints | Privacy screen and Android contact action | Provides the configured contact and user-initiated request workflow. Opening a draft does not send, acknowledge, resolve or register a request. |
| Operational procedures | `docs/PRIVACY_OPERATIONS.md` | Covers request handling, guardian checks, incident response, retention questions and release evidence. These procedures require actual operator adoption. |

The Android files above are under `android/app/src/main/`. Backup exclusions are `res/xml/backup_rules.xml` and `res/xml/data_extraction_rules.xml`. A UI control and its description are not proof of legal or operational effectiveness.

## Verification evidence

The operator utility's five Python tests passed: request/notice/expiry signature binding and tamper rejection, incomplete verification rejection, invalid request/lifetime rejection, prevention of key overwrite, and private-key permission enforcement. Run them with a Python environment containing `cryptography`:

```sh
python3 -m unittest discover -s tools -p 'test_guardian_approval.py' -v
```

App tests must additionally cover consent upgrade, decline, save/read/delete failure, no room/audio processing before consent, guardian approval expiry and request binding, withdrawal during an active session, invalid/replayed peer messages, cancellation/mismatch of connection verification, and loss of a room during authentication. Passing simulated checks does not replace physical Android tests or an independent security review.

## Remaining release requirements

1. Test and staff the privacy inbox and verify the operator's identity/contact presentation.
2. Exercise a secure guardian verification procedure with an authorized operator; never approve solely because an email claims to be a parent.
3. Resolve offline revocation and time-manipulation limitations of guardian approvals before claiming fully effective withdrawal for child users.
4. Obtain a documented retention interpretation under the applicable Act and Rules. Immediate local deletion and transient audio do not by themselves establish compliance with the final Rules' retention provisions.
5. Establish effective user/Board breach-notification delivery and actual rights, nomination and grievance handling.
6. Review the final encrypted transport, dependencies and Android behavior, and record release test evidence.

The legal sources, commencement qualifications and operating procedures are in [Privacy operations](PRIVACY_OPERATIONS.md). The update should be described as added privacy controls and security protections; do not market it as automatically obeying all laws.
