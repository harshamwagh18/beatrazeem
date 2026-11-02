import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/privacy_policy.dart';
import '../core/privacy_store.dart';
import '../core/guardian_approval.dart';

/// Used both before onboarding and as the always-available privacy centre.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({
    super.key,
    required this.store,
    required this.onAccepted,
    required this.onWithdraw,
    required this.requiredBeforeUse,
    this.consent,
    this.username,
    this.roomName,
    this.members = const [],
  });
  final PrivacyStore store;
  final Future<void> Function() onAccepted, onWithdraw;
  final bool requiredBeforeUse;
  final PrivacyConsent? consent;
  final String? username, roomName;
  final List<String> members;
  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  final approval = TextEditingController();
  bool guardian = false, adult = false, agreed = false, working = false;
  String? requestId, message;
  String requestType = 'Access to my data';
  String? preparedRequest;
  @override
  void dispose() {
    approval.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (working) return;
    setState(() {
      working = true;
      message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => message = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> draft(String subject, String body) async {
    preparedRequest = 'Subject: $subject\n$body';
    final opened = await widget.store.composeEmail(
      to: PrivacyPolicy.contactEmail,
      subject: subject,
      body: body,
    );
    if (mounted) {
      setState(
        () => message = opened
            ? 'Draft opened. Review it and send it in your email app.'
            : 'No email app is available. Use Copy request, then send it to ${PrivacyPolicy.contactEmail}.',
      );
    }
  }

  String get dataSummary =>
      'Beatrazeem local data\n'
      'Display name: ${widget.username ?? 'Not saved'}\n'
      'Notice accepted: ${widget.consent?.noticeVersion ?? 'Not accepted'}\n'
      'Accepted at (UTC): ${widget.consent?.acceptedAt.toIso8601String() ?? '—'}\n'
      'Eligibility: ${widget.consent == null
          ? 'Not confirmed'
          : widget.consent!.adultConfirmed
          ? 'Adult self-consent'
          : 'Guardian approval'}\n'
      'Current room: ${widget.roomName ?? 'None'}\n'
      'Current recipients: ${widget.members.isEmpty ? 'None' : widget.members.join(', ')}\n'
      'Audio: temporary playback buffers only; no saved recording.\n'
      'Prior room/member history is not retained. This summary covers this phone, not emails held by the operator.';

  String get requestBody =>
      'To ${PrivacyPolicy.operatorName},\n\n'
      'I would like to request: $requestType.\n'
      'Notice version: ${PrivacyPolicy.noticeVersion}\n\n'
      'Please tell me what proportionate verification is needed and how to provide it securely.\n'
      'Details I choose to provide: [describe your request here]\n\n'
      'Do not include passwords, identity documents or private audio in this email.';

  Future<void> accept() => run(() async {
    if (!agreed || (!guardian && !adult)) return;
    String? token;
    if (guardian) {
      final id = await widget.store.readApprovalRequestId();
      token = approval.text.trim();
      if (id == null || await GuardianApproval.verify(token, id) == null) {
        throw StateError(
          'Approval is invalid, expired, or belongs to another phone or notice. Ask your parent or guardian to contact gamelauncher.',
        );
      }
    }
    await widget.store.saveConsent(
      noticeVersion: PrivacyPolicy.noticeVersion,
      adultConfirmed: !guardian,
      guardianApproval: token,
    );
    await widget.onAccepted();
  });

  Future<void> withdraw() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw and delete local data?'),
        content: const Text(
          'Sharing stops and this phone leaves its room. The saved name, consent receipt and guardian approval/request are erased. Other phones cannot be remotely erased. Requests already emailed to gamelauncher require a separate erasure request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Withdraw and delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await run(widget.onWithdraw);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Privacy & your data',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 10),
      const Text('gamelauncher · gamelauncher223@gmail.com'),
      const SizedBox(height: 12),
      const Text(
        'Your display name is saved locally. Approved room members receive names and shared audio. You control when sharing starts and can withdraw here.',
      ),
      ExpansionTile(
        initiallyExpanded: widget.requiredBeforeUse,
        tilePadding: EdgeInsets.zero,
        title: const Text('Read the privacy notice'),
        children: [
          SelectableText(
            PrivacyPolicy.notice,
            style: const TextStyle(height: 1.5),
          ),
          const SizedBox(height: 16),
        ],
      ),
      if (widget.requiredBeforeUse) ...[
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Parent or lawful guardian approval'),
          subtitle: const Text(
            'Required if you are under 18 or need a lawful guardian to consent.',
          ),
          value: guardian,
          onChanged: working
              ? null
              : (v) => setState(() {
                  guardian = v;
                  adult = false;
                  agreed = false;
                }),
        ),
        if (!guardian)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'I am 18 or older and can give consent for myself.',
            ),
            value: adult,
            onChanged: working
                ? null
                : (v) => setState(() => adult = v ?? false),
          ),
        if (guardian) ...[
          const Text(
            'A parent or guardian must complete verification with gamelauncher before this phone can join rooms. Ask for a secure verification method; do not email identity documents.',
          ),
          OutlinedButton(
            onPressed: working
                ? null
                : () => run(() async {
                    final id = await widget.store
                        .getOrCreateApprovalRequestId();
                    if (mounted) setState(() => requestId = id);
                    await draft(
                      'Beatrazeem guardian approval request',
                      'I am the parent or lawful guardian requesting approval for this phone.\n'
                          'Request reference: $id\nNotice version: ${PrivacyPolicy.noticeVersion}\n\n'
                          'Please provide your secure process to verify my identity, adulthood and parental/guardian authority and record informed consent. This email alone is not verified consent.',
                    );
                  }),
            child: const Text('Request guardian verification'),
          ),
          if (requestId != null)
            SelectableText('Phone request reference: $requestId'),
          TextField(
            controller: approval,
            maxLength: 4096,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Verified approval from gamelauncher',
              counterText: '',
            ),
            enabled: !working,
            autocorrect: false,
            enableSuggestions: false,
          ),
        ],
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            guardian
                ? 'The verified guardian approved this notice and this phone’s use.'
                : 'I agree to the personal-data uses described in this notice.',
          ),
          value: agreed,
          onChanged: working
              ? null
              : (v) => setState(() => agreed = v ?? false),
        ),
        FilledButton(
          onPressed: working || !agreed || (!guardian && !adult)
              ? null
              : accept,
          child: Text(working ? 'Checking…' : 'Accept and continue'),
        ),
        TextButton(
          onPressed: working ? null : () => SystemNavigator.pop(),
          child: const Text('Decline and exit'),
        ),
      ],
      const Divider(height: 32),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Data on this phone'),
        children: [
          SelectableText(dataSummary),
          TextButton(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: dataSummary)),
            child: const Text('Copy my data summary'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        'Privacy requests & complaints',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      DropdownButtonFormField<String>(
        initialValue: requestType,
        isExpanded: true,
        items: const [
          'Access to my data',
          'Correct my data',
          'Erase my data',
          'Withdraw guardian consent',
          'Nominate a representative',
          'Privacy complaint',
          'Report a data breach',
        ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: working
            ? null
            : (v) => setState(() {
                requestType = v!;
                preparedRequest = null;
              }),
      ),
      OutlinedButton(
        onPressed: working
            ? null
            : () => run(() => draft('Beatrazeem: $requestType', requestBody)),
        child: const Text('Open email request'),
      ),
      TextButton(
        onPressed: () => Clipboard.setData(
          ClipboardData(
            text:
                'To: ${PrivacyPolicy.contactEmail}\n${preparedRequest ?? requestBody}',
          ),
        ),
        child: const Text('Copy request'),
      ),
      const Text(
        'Review and send the draft yourself. No request is submitted automatically. Acknowledgement: 7 days; resolution: 30 days under our service policy.',
      ),
      const SizedBox(height: 18),
      OutlinedButton(
        onPressed: working ? null : withdraw,
        child: const Text('Withdraw consent & delete local data'),
      ),
      if (message != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(message!, key: const ValueKey('privacy-message')),
        ),
    ],
  );
}
