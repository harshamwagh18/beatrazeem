# Beatrazeem privacy operations and release requirements

Updated 3 November 2026 for version 0.9.1 (build 17). This document describes the current interface and the operator work that remains. It does not certify legal compliance. A displayed contact, a self-declared age or passing software tests do not establish effective request handling or verified parental consent.

## Current release and responsibility

The responsible operator is **gamelauncher**. The user supplied **gamelauncer223@gmail.com** as the new contact for this release. This differs from the preceding address, `gamelauncher223@gmail.com`; the exact previous notice is preserved at [2026-11-02.1](privacy-notices/2026-11-02.1.md). Mailbox ownership, delivery, staffing and operator identity have not been independently verified. Confirm them before distribution.

The privacy screen displays “If you have any queries, contact gamelauncer223@gmail.com.” It no longer has a request-category selector, email-draft button, copy-request button or guardian approval controls. Users send correspondence through their own email app. The local data summary, notice, profile correction and withdrawal/deletion remain available.

Onboarding now requires affirmative confirmation that the user is **9 or older**, plus agreement to notice **2026-11-03.1**. This is a self-declaration. It does not verify age, establish adulthood or provide verified parental consent for users aged 9–17. The release no longer offers the previous operator-signed guardian approval route. Do not describe the new age checkbox as a substitute for verified parental or lawful-guardian consent, or claim that this version obeys all laws.

Determine the roles of the app operator, creator and listeners, including any applicable personal/domestic exception, lawful basis and child/guardian requirements for the intended deployment. Record the decision, purposes, data categories, recipients, retention and responsible owner. Reassess when adding analytics, accounts, cloud relays, advertising, payments, support tooling or remote crash collection.

## Data inventory to verify against each release

| Data | Purpose and expected location | Operator action |
|---|---|---|
| Display username | Identify a person in a nearby room; saved in private app storage and shared with admitted members | Keep correction/deletion available; names are display labels, not verified identities |
| Current consent receipt | Notice version, acceptance timestamp and minimum-age self-declaration; private phone storage | Preserve exact notice versions; do not interpret minimum-age confirmation as verified adulthood or parental consent |
| Legacy privacy records | An older receipt or guardian approval/request reference may exist on an updated installation until replaced or deleted | The old receipt cannot bypass the current notice; accepting the new notice removes obsolete guardian data, while withdrawal deletes local profile and privacy records |
| Room name and member list | Show the current listening group | Clear session data when the room ends; no historical member list is kept |
| Microphone and captured app audio | Live transmission and playback through temporary buffers | Explain capture and provide stop controls; do not introduce recordings silently |
| Local network addresses and timing messages | Discover, authenticate and synchronize nearby devices | Distinguish visible metadata from encrypted room content |
| Operator correspondence | Resolve questions, requests, grievances or incidents sent to the contact address | Inventory email-provider access, retention, recipients and relevant agreements |

Check the actual build, dependencies, Android backup behavior and support systems before treating this inventory as complete.

## Notice, migration and withdrawal

Give the current notice before saving a new profile or starting room discovery/capture. Existing users must explicitly accept the changed notice; the earlier receipt is not automatically reinterpreted. A saved username is retained during the upgrade. The age checkbox and notice agreement start unchecked. Android microphone and projection permissions remain separate.

Keep the exact notice text with its version so local receipts can be interpreted. The current notice is [2026-11-03.1](PRIVACY_NOTICE.md); [2026-11-02.1](privacy-notices/2026-11-02.1.md) is historical and must not be used as current onboarding instructions.

Users can review their local data, stop sharing, leave, correct their name in Profile, or withdraw and delete. Withdrawal stops capture/output and leaves the room before erasing the local profile and privacy records. Failed persistence or deletion must not be described as success. Keep room use blocked while deletion is retried. Clearing this phone cannot erase another person's recordings or correspondence already sent to the operator.

## Contact, rights and grievance handling

Removing the request form does not remove the need to operate the published contact channel. The operator should:

1. Monitor the inbox and assign a request owner and backup. Log receipt date, type, response target and status with minimal identifiers. The app does not send or register requests.
2. Follow the notice's published service policy: acknowledge within 7 days and resolve within 30 days. Provide help to users who cannot use the local controls.
3. Verify entitlement proportionately before disclosing or changing operator-held information. A room display name alone is not proof of identity. Do not routinely ask for identity documents or private audio by ordinary email.
4. For access, explain information actually processed and relevant recipients, distinguishing local device data from operator-held correspondence. Do not invent server records or historical room lists.
5. For correction/erasure, use local controls where appropriate, review operator-held records and explain any lawful retention restriction. Confirm what was completed and what remains.
6. Handle nomination requests through the contact address using a secure process for authority, scope and later exercise. An email alone does not establish a verified nomination.
7. Resolve grievances and verify the applicable official escalation channel before directing users to file a complaint. A government information page is not necessarily a functioning complaint portal.

## Children and lawful guardians: changed capability

Version 0.9.1 permits entry following a self-declaration of age 9 or older and acceptance of the notice. It has no guardian-verification request or token-entry flow. No age or identity verification service is connected. This is a material change from 0.9.0, not evidence that child/guardian obligations have been fulfilled.

Resolve the applicable requirements and provide an effective consent/withdrawal process before claiming verified parental consent or full compliance for child use. Consider users who require a lawful guardian as well as children. Consent from someone operating a microphone does not independently establish consent from every identifiable person whose voice is transmitted.

The historical `tools/guardian_approval.py` and `lib/core/guardian_approval.dart` may remain for source history/testing. They do not enable guardian enrolment in this release. Do not generate or send approvals expecting the current interface to import them. Keep any existing private signing key and verification evidence outside the app and source archive; never include them in Git, screenshots or diagnostic logs. Any operator records from earlier approvals need their own access, retention and erasure decisions.

## Security and incidents

Compare both phones' security codes before approving a connection. The six-digit room discovery code does not replace authenticated connection verification. Personal room payloads are encrypted, while discovery and traffic metadata can remain visible. Keep authentication, replay rejection, bounded queues and disconnect cleanup covered by tests and independent review.

For an incident, assign a lead, record awareness time, contain the affected processing, preserve relevant evidence under a documented retention decision, identify affected data/users and assess notification obligations. Prepare accessible communications describing the incident, consequences, mitigation, recommended action and business contact. This local-only app has no central user address book or remote notification service, so effective delivery is an operator requirement. Nothing in this app or document automatically sends a statutory report.

Restrict incident records. Exclude audio content, room keys, secret connection material and unrelated personal data from diagnostics. Record preventive follow-up work. Review additional applicable incident-reporting rules separately.

## Legal review retained from 2 November 2026

The following legal-source assessment was recorded for 0.9.0. This UI update does not revalidate that assessment or establish that this build meets those requirements.

The main app-facing Act obligations are scheduled eighteen months after the November 2025 Gazette publication; planning uses May 2027. This differs from provisions already commenced. See the [Act commencement notification](https://www.meity.gov.in/static/uploads/2025/11/c56ceae6c383460ca69577428d36828b.pdf).

When the relevant Rules apply: Rule 7 requires affected-user and initial Board notification without delay, followed by detailed Board information within 72 hours of awareness, unless the Board permits longer. Rule 14 requires a published grievance response period no longer than 90 days. Rules 6(1)(e) and 8(3) contain one-year security/personal-data/traffic/log retention requirements. Rule 8(1)'s separate inactivity periods apply to specified classes; they are not a universal deletion timer. Rule 10 concerns verifiable parental consent; Rule 11 concerns lawful guardians. These Rules' principal app-facing provisions also have an eighteen-month commencement period. See the [final 2025 Rules](https://www.meity.gov.in/static/uploads/2025/11/53450e6e5dc0bfa85ebd78686cadad39.pdf) and [December 2025 corrigendum](https://www.meity.gov.in/static/uploads/2025/12/3c7ebbae0e5456f493f486e6845df86b.pdf).

**Unresolved release requirement:** obtain and document an applicable retention interpretation for Beatrazeem's local peer processing and operator-held records before the relevant obligations commence or claiming compliance. The current transient-audio design and immediate local deletion are not proof that Rules 6 and 8 are satisfied. Do not silently start recording audio for a year to resolve this issue. Any required retention architecture needs a separate necessity, security, notice and access design. Likewise, never promise deletion of legally retained records without explaining the restriction.

The [October 2026 Removal of Difficulties Order](https://www.meity.gov.in/static/uploads/2026/10/daf495a7b5798a3dfa72a944b51fc176.pdf) clarifies guardian wording and data-audit terminology. Significant Data Fiduciary duties require assessment if the operator is designated; a special DPO and independent auditor are not automatically required for every small app.

## Public-release evidence checklist

- Confirmed operator identity and a reachable, staffed current contact address.
- Accurate notice and data inventory for this exact build.
- Documented decision and effective process for child and lawful-guardian requirements; the 9+ checkbox is not verified parental consent.
- Requests, nomination and grievance handling tested from actual email receipt to response.
- Retention/erasure decisions for local processing, correspondence and any historical verification records.
- Effective affected-user and regulator incident-notification procedure.
- Applicable processor, cross-border and store-disclosure assessment.
- Physical multi-phone tests and independent security review, including encrypted-audio performance.

Record evidence and responsible owners. Code changes and removed buttons do not establish that Beatrazeem obeys all laws.
