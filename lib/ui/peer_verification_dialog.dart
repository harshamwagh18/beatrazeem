import 'dart:async';
import 'package:flutter/material.dart';
import '../core/transport.dart';

class PeerVerificationDialog extends StatefulWidget {
  const PeerVerificationDialog({super.key, required this.verification});
  final PeerVerification verification;
  @override
  State<PeerVerificationDialog> createState() => _PeerVerificationDialogState();
}

class _PeerVerificationDialogState extends State<PeerVerificationDialog> {
  late final Timer deadline;
  bool compared = false;
  @override
  void initState() {
    super.initState();
    deadline = Timer(const Duration(seconds: 75), () {
      if (mounted) Navigator.of(context).pop(false);
    });
  }

  @override
  void dispose() {
    deadline.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Compare security codes'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.verification.isHost
                ? 'Compare with the person joining your room.'
                : 'Compare with the creator’s phone.',
          ),
          const SizedBox(height: 18),
          SelectableText(
            widget.verification.verificationCode,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              letterSpacing: 5,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Both phones must show these same six digits. Reject if they differ or you do not recognize the other device. Names and audio are shared after both confirm.',
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: compared,
            onChanged: (value) => setState(() => compared = value ?? false),
            title: const Text('I compared both phones. The codes match.'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Reject'),
      ),
      FilledButton(
        onPressed: compared ? () => Navigator.pop(context, true) : null,
        child: const Text('Approve device'),
      ),
    ],
  );
}
