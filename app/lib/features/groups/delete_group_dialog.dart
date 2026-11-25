import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/pin_store.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../spaces/spaces_repository.dart';

/// Asks for the PIN before a whole group is deleted, so it never happens by
/// a wrong tap. Without a PIN on this phone, the group name is typed instead.
class DeleteGroupDialog extends ConsumerStatefulWidget {
  const DeleteGroupDialog({super.key, required this.space});
  final Space space;

  @override
  ConsumerState<DeleteGroupDialog> createState() => _DeleteGroupDialogState();
}

class _DeleteGroupDialogState extends ConsumerState<DeleteGroupDialog> {
  final _text = TextEditingController();
  bool? _pinSet;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(pinStoreProvider).isSet.then((v) {
      if (mounted) setState(() => _pinSet = v);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy || _pinSet == null || _text.text.trim().isEmpty) return;
    final l = AppLocalizations.of(context);
    final store = ref.read(pinStoreProvider);
    setState(() => _busy = true);
    String? error;
    if (_pinSet!) {
      switch (await store.verify(_text.text.trim())) {
        case PinResult.ok:
          break;
        case PinResult.wrong:
          error = l.wrongPin(
            PinStore.maxAttemptsBeforeLock - await store.failedAttempts(),
          );
        case PinResult.lockedOut:
          error = l.lockedOut(await store.lockoutSecondsLeft());
      }
    } else if (_text.text.trim() != widget.space.name.trim()) {
      error = l.deleteGroupNameWrong;
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
      if (_pinSet!) _text.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final pin = _pinSet ?? true;
    final others = widget.space.memberCount - 1;
    return AlertDialog(
      scrollable: true,
      title: Text(l.deleteGroupTitle(widget.space.name)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.deleteGroupWarning),
          if (others > 0) ...[
            const SizedBox(height: Tokens.s2),
            Text(
              l.deleteGroupOthers(others),
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: Tokens.s4),
          TextField(
            controller: _text,
            enabled: _pinSet != null && !_busy,
            obscureText: pin,
            keyboardType: pin ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(
              labelText: pin ? l.deleteGroupPin : l.deleteGroupName,
              errorText: _error,
              errorMaxLines: 3,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: _busy || _pinSet == null || _text.text.trim().isEmpty
              ? null
              : _confirm,
          child: Text(l.deleteGroupYes),
        ),
      ],
    );
  }
}
