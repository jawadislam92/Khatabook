import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/big_button.dart';
import '../../core/widgets/screen_scaffold.dart';
import '../../l10n/app_localizations.dart';
import '../spaces/spaces_repository.dart';
import '../auth/pending_invite.dart';
import 'groups_models.dart';
import 'groups_repository.dart';
import 'role_labels.dart';

class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, this.token});
  final String? token;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _input = TextEditingController();
  InvitePreview? _preview;
  String? _token;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // This screen now holds the invite; stop the router sending us here.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(pendingInviteProvider.notifier).clear(),
    );
    if (widget.token != null) {
      _input.text = widget.token!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final l = AppLocalizations.of(context);
    final token = InviteLink.parse(_input.text);
    if (token == null) {
      setState(() => _error = l.inviteNotFound);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    try {
      final p = await ref.read(groupsRepositoryProvider).previewInvite(token);
      if (!mounted) return;
      setState(() {
        _token = token;
        _preview = p;
        _error = p == null
            ? l.inviteNotFound
            : (p.valid ? null : l.inviteInvalid);
      });
    } catch (_) {
      if (mounted) setState(() => _error = l.errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final spaceId = await ref
          .read(groupsRepositoryProvider)
          .acceptInvite(_token!);
      ref.invalidate(mySpacesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.joined(_preview!.spaceName))));
      context.go('/space/$spaceId');
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l.inviteInvalid;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = _preview;
    return ScreenScaffold(
      title: l.joinGroup,
      children: [
        Text(l.joinHint, style: text.bodyLarge),
        const SizedBox(height: Tokens.s4),
        TextField(
          controller: _input,
          maxLines: 3,
          minLines: 1,
          style: const TextStyle(fontFamily: 'Roboto'),
          decoration: InputDecoration(
            labelText: l.inviteLinkOrCode,
            prefixIcon: const Icon(Icons.link),
          ),
          onSubmitted: (_) => _check(),
        ),
        const SizedBox(height: Tokens.s3),
        BigButton(
          label: l.checkInvite,
          onPressed: _check,
          busy: _busy && p == null,
          outlined: true,
        ),
        if (_error != null) ...[
          const SizedBox(height: Tokens.s4),
          Text(
            _error!,
            style: text.bodyLarge?.copyWith(
              color: scheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (p != null && p.valid) ...[
          const SizedBox(height: Tokens.s5),
          Container(
            padding: const EdgeInsets.all(Tokens.s4),
            decoration: BoxDecoration(
              color: Tokens.saffron.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(Tokens.radius),
              border: Border.all(color: Tokens.saffronDeep),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.family_restroom_rounded,
                  size: 36,
                  color: Tokens.saffronDeep,
                ),
                const SizedBox(width: Tokens.s3),
                Expanded(
                  child: Text(
                    l.invitePreviewText(
                      p.inviterName ?? '',
                      p.spaceName,
                      roleLabel(l, p.role),
                    ),
                    style: text.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s4),
          BigButton(
            label: l.join,
            icon: Icons.check,
            onPressed: _join,
            busy: _busy,
          ),
        ],
      ],
    );
  }
}
