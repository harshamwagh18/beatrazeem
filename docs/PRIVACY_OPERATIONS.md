# Beatrazeem privacy operations and release requirements

Reviewed 2 November 2026. This document accompanies privacy engineering changes; it does not certify legal compliance. The operator must implement the procedures below and resolve the marked release requirements. Software features do not establish that an email inbox is staffed, a legal exception applies, a parental consent is verifiable, or a statutory report has been filed.

## Responsibility and release configuration

The user has designated **gamelauncher** as the responsible operator and **gamelauncher223@gmail.com** as the privacy and grievance contact. These are user-supplied details; mailbox delivery, staffing, business identity and response handling have not been independently verified. Before public distribution, confirm ownership and delivery with a real test request and publish the approved details in the app. Do not substitute a GitHub commit email, guessed address or example address. A configured address does not establish an effective support process.

Determine the roles of the app operator, creator and listeners, including whether processing is personal/domestic under section 3(c)(i), and whether the operator is a Data Fiduciary for each activity. Nearby or local-only processing is not an automatic exemption. Record the decision, purposes, data categories, recipients, lawful basis, retention and responsible owner. Reassess when adding analytics, accounts, cloud relays, advertising, payments, support tooling or remote crash collection.

## Data inventory to verify against each release

| Data | Purpose and expected location | Operator action |
|---|---|---|
| Display username | Identify the person in a nearby room; saved in the phone's private app storage and shared with admitted members | Keep correction/deletion available; explain that names are display labels, not verified identities |
| Consent receipt | Notice version, affirmative decision, local timestamp and eligibility declaration; private phone storage | Keep the exact notice version in source history; do not claim that a local record alone proves a person's age or identity |
| Room name and member list | Show the current listening group on its devices | Clear session data when the room ends; do not add room history without reviewing the purpose and notice |
| Microphone and captured app audio | Live transmission and playback; transient processing buffers | Explain capture before starting and provide stop controls; do not introduce recordings silently |
| Local network addresses and timing messages | Discover, authenticate and synchronize nearby devices | Distinguish visible network metadata from encrypted room content; network encryption does not hide that a connection exists |
| Privacy correspondence | Resolve user-initiated requests, grievances or incidents through the configured contact channel | Inventory the email provider, access permissions, retention, recipients and any processor contract |

These entries describe the intended architecture. Check the actual release, dependencies, Android backup behavior and support systems before treating the inventory as complete.

## Notice, choice and withdrawal

Give the standalone notice before saving a new profile or starting discovery/capture. Existing profiles need the current notice and an affirmative choice when upgrading. Describe each personal-data category, purpose, recipients, storage and retention, contact, withdrawal method, rights request method and Board escalation route. The notice should be understandable independently of the general help text. Keep Android microphone/projection approval as an additional permission, not the sole privacy consent record.

Users should be able to review the notice later, stop capture immediately, leave a room, correct their username, and withdraw consent/delete local profile data. A failed persistence or deletion operation must not be described as successful. Stop processing while deletion is retried. Explain accurately which copies the app can delete; another person's independent recordings, exported files and email correspondence cannot be erased by clearing this phone.

Retain approved notice versions outside the app so a versioned consent receipt can be interpreted. Do not retroactively change what an already-recorded version means. Avoid broad consent to unrelated future purposes.

## Rights and grievance handling

Recommended operating procedure, to be adopted by the operator:

1. Monitor the published inbox on working days and assign a named request owner and backup. Log the received date, request type, due date and status with minimal necessary identifiers. An app opening a draft email does not establish receipt or submission.
2. Follow the published service policy: acknowledge within 7 days and resolve within 30 days. Acknowledge a received request, state the response target and include the published business contact. Offer help to a user who cannot use the app controls.
3. Verify entitlement proportionately before disclosing information or changing records. A room display name alone does not establish identity. Do not routinely request an Aadhaar copy, complete audio recording or broad device export.
4. For access requests, describe the data actually processed, purposes and relevant recipients/processors. State what is held only on the user's device and what the operator cannot retrieve. Do not invent server-held records or historical recipient lists.
5. For correction or erasure, use the local controls where appropriate, search operator-held correspondence and applicable processors, and explain any lawful retention restriction. Confirm what was completed, what remains and why.
6. Accept nomination requests through the published channel. Record the scope and minimal nominee details securely; establish a process to verify the nominator, nominee and death/incapacity before acting. A prefilled nomination email is only a request, not a verified or registered nomination.
7. Resolve grievances through the operator's process and explain the applicable Board escalation procedure after that process is exhausted. Confirm the Board's current official filing channel before directing a user to submit. Do not present a general government information page as a functioning complaint portal.

## Verified parental and lawful-guardian approval

Children are supported only through an operator-reviewed guardian route. Before that route succeeds, the app must block profile creation, room discovery and audio sharing. The device creates a random request identifier and displays the current notice version. The guardian contacts gamelauncher using the published address to arrange verification. **Do not send identity documents, a child's voice recording or diagnosis in ordinary email.** Use an appropriately secured verification channel or a reliable identity/age service after reviewing its purpose, provider and contract.

The operator must complete the following checks before issuing any approval:

1. Match the request identifier to the app instance being approved. Show the guardian the exact privacy notice/version and identify the intended processing, room recipients, withdrawal method and meaningful risks.
2. Establish the guardian's identity and adulthood using reliable evidence or an appropriate verified identity/age source. Record the verification outcome and evidence reference securely; do not keep unnecessary copies of documents.
3. Establish parenthood or lawful authority for the person whose processing is being approved. For a relevant adult with a lawful guardian, use the legally appropriate guardianship evidence. A person knowing the room code does not establish authority.
4. Obtain and record a clear affirmative, informed consent for the specified processing. Record reviewer, date, request identifier, notice version, scope, evidence references and consent method in an access-controlled operator record with an approved retention period.
5. Only after all checks, issue a short-lived signed approval. Deliver it through the verified guardian's channel. Explain the expiry, device binding and withdrawal limitations. The child/device holder pastes the approval into the app.

A checkbox, payment card, ordinary email address or a signature generated by the helper does not independently verify identity, age, authority or consent. The signing utility records no verification evidence and performs none of those checks; the operator is responsible for them. The release cannot be described as supporting legally verified parental consent until the verification operation is actually staffed and exercised. The gate is an enforcement mechanism for an operator decision.

### Operator signing utility

The app trusts the deployment public key. Its corresponding private key is stored outside the source repository at `work/private-beatrazeem/guardian-key.pem` in this development workspace, accessible only to its owner. It must not be packaged in an APK, source ZIP, Git repository, screenshots or diagnostic logs. Protect an encrypted operator backup and restrict signing access. Losing the key stops new approvals; suspected compromise requires a new key and app update.

The utility requires Python and the `cryptography` package. From the app source directory, after completing the actual verification:

```sh
python3 tools/guardian_approval.py issue \
  --private-key ../private-beatrazeem/guardian-key.pem \
  --request-id REQUEST_IDENTIFIER_FROM_THE_APP \
  --notice-version EXACT_NOTICE_VERSION_FROM_THE_APP \
  --days 30 \
  --verified-identity \
  --verified-adulthood \
  --verified-authority \
  --recorded-consent
```

Replace the two capitalized values with the exact app values. The command rejects missing confirmations, invalid request IDs and lifetimes outside 1–90 days. Default expiry is 30 days. Its output is a signed approval; it contains only a version, random request ID, notice version, issued time and expiry. It contains no parent/child name, date of birth or identity document. Keep the verification record separately. Do not treat the four command flags as evidence that verification occurred.

For a separate deployment, `python3 tools/guardian_approval.py init --private-key /protected/outside-repository/guardian-key.pem` creates an exclusive new key and prints only its public key. Configure that public key in the matching app build; do not rotate the production trust key accidentally.

### Withdrawal and offline limits

In-app withdrawal must stop capture/output, disconnect, delete the local profile/consent and invalidate the approval/request identifier so a copied old approval cannot re-enable that installation. The operator must accept a guardian's withdrawal request and assist with deletion on the affected device. A disconnected device cannot receive immediate remote revocation in this design: the signed approval remains usable until local invalidation or expiry. This limitation needs legal and operational resolution before claiming fully effective guardian withdrawal for deployed child users. Do not describe operator email as remote revocation or extend approvals automatically.

Device time can also affect offline expiry enforcement. Test clock changes and retain trustworthy time observations where feasible; an offline bearer approval is not equivalent to a continuously checked authorization service. Children must not be silently switched to an adult path to bypass verification. The consent of the person operating a microphone also does not establish consent from every identifiable bystander whose voice is transmitted.

## Security and incident procedure

Use connection verification exactly as instructed in the app before approving a peer. A six-digit discovery code is not a replacement for authenticated encryption. Review cryptographic dependencies, handshake state, replay rejection, message bounds, admission limits, key lifetime and disconnect cleanup. Test rejected/unverified peers, invalid authentication tags, old clients, source changes, app restarts and deletion during an active room. Review metadata exposure and denial-of-service risks separately.

For an incident, the operator should assign an incident lead, record when it became aware, contain the affected processing, preserve only relevant evidence under a documented lawful retention decision, identify affected people and data, and assess disclosure obligations. Prepare concise user communications describing what happened, likely consequences, mitigation, recommended action and the business contact. Use an effective channel the user can access. This local-only app does not currently establish a central address book or remote notification service, so reliable delivery to affected users is an operational release requirement. No report or notification is automatically sent by these documents.

Keep incident access restricted. Do not include audio content, full room keys, secret connection material or unrelated personal data in diagnostic output. Conduct a follow-up review and record preventive actions. Review any additional applicable incident-reporting law independently; the DPDP timetable is not an exemption from other law.

## Verified timing and retention requirements

The main app-facing Act obligations are scheduled eighteen months after the November 2025 Gazette publication; planning uses May 2027. This differs from provisions already commenced. See the [Act commencement notification](https://www.meity.gov.in/static/uploads/2025/11/c56ceae6c383460ca69577428d36828b.pdf).

When the relevant Rules apply: Rule 7 requires affected-user and initial Board notification without delay, followed by detailed Board information within 72 hours of awareness, unless the Board permits longer. Rule 14 requires a published grievance response period no longer than 90 days. Rules 6(1)(e) and 8(3) contain one-year security/personal-data/traffic/log retention requirements. Rule 8(1)'s separate inactivity periods apply to specified classes; they are not a universal deletion timer. Rule 10 concerns verifiable parental consent; Rule 11 concerns lawful guardians. These Rules' principal app-facing provisions also have an eighteen-month commencement period. See the [final 2025 Rules](https://www.meity.gov.in/static/uploads/2025/11/53450e6e5dc0bfa85ebd78686cadad39.pdf) and [December 2025 corrigendum](https://www.meity.gov.in/static/uploads/2025/12/3c7ebbae0e5456f493f486e6845df86b.pdf).

**Unresolved release requirement:** obtain and document an applicable retention interpretation for Beatrazeem's local peer processing and operator-held records before the relevant obligations commence or claiming compliance. The current transient-audio design and immediate local deletion are not proof that Rules 6 and 8 are satisfied. Do not silently start recording audio for a year to resolve this issue. Any required retention architecture needs a separate necessity, security, notice and access design. Likewise, never promise deletion of legally retained records without explaining the restriction.

The [October 2026 Removal of Difficulties Order](https://www.meity.gov.in/static/uploads/2026/10/daf495a7b5798a3dfa72a944b51fc176.pdf) clarifies guardian wording and data-audit terminology. Significant Data Fiduciary duties require assessment if the operator is designated; a special DPO and independent auditor are not automatically required for every small app.

## Public-release evidence checklist

- Approved operator identity and reachable, staffed business contact.
- Current notice and truthful data inventory for this exact build.
- The child/guardian verification operation exercised end to end, including evidence handling, expiry and withdrawal limitations.
- Rights, nomination and grievance requests tested from draft to actual operator response.
- Retention/erasure decision documented for app and operator-held records.
- Effective affected-user/Board incident-notification procedure.
- Processor contracts and cross-border arrangements assessed where applicable.
- Independent security review and physical multi-phone tests, including encrypted audio performance.
- Any distribution-store disclosures and other applicable laws reviewed separately.

Record evidence and responsible owners; do not mark a requirement complete merely because a UI button or this checklist exists. Code changes alone cannot justify the statement that Beatrazeem obeys all laws.
