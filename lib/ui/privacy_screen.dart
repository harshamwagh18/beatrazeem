import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/privacy_policy.dart';
import '../core/privacy_store.dart';

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
  bool working = false;
  String? message;

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

  String get dataSummary =>
      'Beatrazeem local data\n'
      'Display name: ${widget.username ?? 'Not saved'}\n'
      'Notice accepted: ${widget.consent?.noticeVersion ?? 'Not accepted'}\n'
      'Accepted at (UTC): ${widget.consent?.acceptedAt.toIso8601String() ?? '—'}\n'
      'Agreement: ${widget.consent == null
          ? 'Not confirmed'
          : widget.consent!.noticeAccepted
          ? 'Accepted by continuing'
          : 'Earlier notice — new confirmation required'}\n'
      'Current room: ${widget.roomName ?? 'None'}\n'
      'Current recipients: ${widget.members.isEmpty ? 'None' : widget.members.join(', ')}\n'
      'Audio: temporary playback buffers only; no saved recording.\n'
      'Prior room/member history is not retained. This summary covers this phone, not emails held by the operator.';

  Future<void> accept() => run(() async {
    await widget.store.saveConsent(
      noticeVersion: PrivacyPolicy.noticeVersion,
      noticeAccepted: true,
    );
    await widget.onAccepted();
  });

  Future<void> withdraw() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw and delete local data?'),
        content: const Text(
          'Sharing stops and this phone leaves its room. The saved name, notice receipt and any earlier age or guardian approval data are erased. Other phones cannot be remotely erased. Requests already emailed to gamelauncher require a separate erasure request.',
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
      const Text(PrivacyPolicy.operatorName),
      const SizedBox(height: 12),
      const Text(
        'Your display name is saved locally. Approved room members receive names and shared audio. You control when sharing starts and can withdraw here.',
      ),
      ExpansionTile(
        initiallyExpanded: widget.requiredBeforeUse,
        tilePadding: EdgeInsets.zero,
        title: const Text('Terms and conditions & privacy notice'),
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
        const Text(
          'By continuing, I agree to the terms and conditions and privacy notice.',
          key: ValueKey('terms-statement'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: working ? null : accept,
          child: Text(working ? 'Saving…' : 'Continue'),
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
      const SelectableText(
        'If you have any queries, contact ${PrivacyPolicy.contactEmail}.',
        key: ValueKey('privacy-contact'),
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
