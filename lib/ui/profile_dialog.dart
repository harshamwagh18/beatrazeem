import 'package:flutter/material.dart';
import '../core/room_member.dart';
import 'design.dart';

class ProfileDialog extends StatefulWidget {
  const ProfileDialog({
    super.key,
    required this.username,
    required this.onSave,
  });
  final String username;
  final Future<void> Function(String) onSave;

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  late final input = TextEditingController(text: widget.username);
  final form = GlobalKey<FormState>();
  bool saving = false;
  String? error;

  Future<void> _save() async {
    if (saving || !(form.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(roomText(input.text, limit: 24, label: 'Username'));
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not save your username. Please try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: const Text('Profile'),
        scrollable: true,
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: InitialAvatar(widget.username, size: 64)),
              const SizedBox(height: 20),
              Text(
                'Change username',
                style: TextStyle(color: c.text, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Saved on this phone for next time. This is the name people see in your room.',
                style: TextStyle(color: c.muted, height: 1.5),
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const ValueKey('profile-username'),
                controller: input,
                enabled: !saving,
                maxLength: 24,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) {
                  try {
                    roomText(value ?? '', limit: 24, label: 'Username');
                    return null;
                  } on FormatException catch (e) {
                    return e.message;
                  }
                },
                onFieldSubmitted: (_) => _save(),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (saving) const LinearProgressIndicator(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Text(saving ? 'Saving…' : 'Save changes'),
          ),
        ],
      ),
    );
  }
}
