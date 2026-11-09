import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/load_error.dart';
import '../../core/widgets/screen_scaffold.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_repository.dart';
import '../spaces/spaces_repository.dart';
import 'groups_models.dart';
import 'groups_repository.dart';
import 'role_labels.dart';

class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key, required this.spaceId});
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final space = ref
        .watch(mySpacesProvider)
        .value
        ?.where((s) => s.id == spaceId)
        .firstOrNull;
    final me = ref.watch(currentUserProvider).value?.id;
    final members = ref.watch(membersProvider(spaceId));
    final lock = ref.watch(lockedUntilProvider(spaceId)).value;
    final myRole = space?.myRole ?? MemberRole.viewer;
    final canInvite = roleAtLeast(myRole, MemberRole.manager);
    final isOwner = myRole == MemberRole.owner;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ScreenScaffold(
      title: l.membersAndSettings,
      children: [
        if (canInvite) ...[
          FilledButton.icon(
            onPressed: () => _invite(context, ref, space?.name ?? ''),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: Text(l.inviteSomeone),
          ),
          const SizedBox(height: Tokens.s4),
        ],
        Text(
          l.members,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: Tokens.s2),
        members.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(Tokens.s5),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => LoadError(
            onRetry: () => ref.invalidate(membersProvider(spaceId)),
          ),
          data: (list) => Column(
            children: [
              for (final m in list) ...[
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          (m.role == MemberRole.owner
                                  ? Tokens.saffronDeep
                                  : Tokens.indigo)
                              .withValues(alpha: 0.15),
                      child: Text(
                        m.name.isEmpty
                            ? '?'
                            : m.name.characters.first.toUpperCase(),
                        style: TextStyle(
                          color: m.role == MemberRole.owner
                              ? Tokens.saffronDeep
                              : Tokens.indigo,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    title: Text(
                      m.userId == me ? '${m.name} (${l.you})' : m.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${roleLabel(l, m.role)}  ·  ${l.entriesByMember(m.entriesCount)}',
                    ),
                    trailing: isOwner && m.userId != me
                        ? PopupMenuButton<String>(
                            onSelected: (v) => v == 'remove'
                                ? _remove(context, ref, m)
                                : _changeRole(context, ref, m),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'role',
                                child: Text(l.changeRole),
                              ),
                              PopupMenuItem(
                                value: 'remove',
                                child: Text(
                                  l.removeFromGroup,
                                  style: TextStyle(color: scheme.error),
                                ),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: Tokens.s2),
              ],
            ],
          ),
        ),
        const SizedBox(height: Tokens.s4),
        Text(
          l.monthLock,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: Tokens.s1),
        Text(
          l.monthLockHint,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Tokens.s2),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Tokens.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      lock == null
                          ? Icons.lock_open_outlined
                          : Icons.lock_outline,
                      color: lock == null
                          ? scheme.onSurfaceVariant
                          : Tokens.saffronDeep,
                    ),
                    const SizedBox(width: Tokens.s2),
                    Expanded(
                      child: Text(
                        lock == null
                            ? l.notLocked
                            : l.lockedUntil(friendlyDate(context, lock)),
                        style: text.titleMedium,
                      ),
                    ),
                  ],
                ),
                if (isOwner) ...[
                  const SizedBox(height: Tokens.s3),
                  Wrap(
                    spacing: Tokens.s2,
                    runSpacing: Tokens.s2,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          final now = DateTime.now();
                          _setLock(ref, DateTime(now.year, now.month, 0));
                        },
                        child: Text(l.lockUpToLastMonth),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: lock ?? DateTime.now(),
                            firstDate: DateTime(2015),
                            lastDate: DateTime.now(),
                          );
                          if (d != null) _setLock(ref, d);
                        },
                        child: Text(l.pickLockDate),
                      ),
                      if (lock != null)
                        TextButton(
                          onPressed: () => _setLock(ref, null),
                          child: Text(l.unlock),
                        ),
                    ],
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: Tokens.s2),
                    child: Text(l.onlyOwner, style: text.bodySmall),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Tokens.s5),
        if (space != null && space.kind == SpaceKind.group)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: () => _leave(context, ref, space),
            icon: const Icon(Icons.logout),
            label: Text(l.leaveGroup),
          ),
      ],
    );
  }

  Future<void> _setLock(WidgetRef ref, DateTime? until) async {
    await ref.read(groupsRepositoryProvider).setLock(spaceId, until);
    ref.read(groupsVersionProvider.notifier).bump();
  }

  Future<void> _invite(
    BuildContext context,
    WidgetRef ref,
    String spaceName,
  ) async {
    final l = AppLocalizations.of(context);
    var role = MemberRole.member;
    final chosen = await showModalBottomSheet<MemberRole>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.s4,
            0,
            Tokens.s4,
            Tokens.s4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.inviteAs,
                style: Theme.of(ctx).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: Tokens.s2),
              RadioGroup<MemberRole>(
                groupValue: role,
                onChanged: (v) => setState(() => role = v!),
                child: Column(
                  children: [
                    for (final r in [
                      MemberRole.manager,
                      MemberRole.member,
                      MemberRole.viewer,
                    ])
                      RadioListTile<MemberRole>(
                        value: r,
                        title: Text(roleLabel(l, r)),
                        subtitle: Text(roleHint(l, r)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Tokens.s3),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, role),
                child: Text(l.invite),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    final token = await ref
        .read(groupsRepositoryProvider)
        .createInviteToken(spaceId, chosen);
    final link = InviteLink.build(token);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.inviteLinkReady, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: Tokens.s3),
            SelectableText(
              link,
              style: const TextStyle(fontFamily: 'Roboto', fontSize: 13),
            ),
            const SizedBox(height: Tokens.s4),
            FilledButton.icon(
              onPressed: () => SharePlus.instance.share(
                ShareParams(text: l.inviteMessage(spaceName, link)),
              ),
              icon: const Icon(Icons.share_outlined),
              label: Text(l.shareLink),
            ),
            const SizedBox(height: Tokens.s2),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text(l.copied)));
                }
              },
              icon: const Icon(Icons.copy_outlined),
              label: Text(l.copyLink),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeRole(
    BuildContext context,
    WidgetRef ref,
    Member m,
  ) async {
    final l = AppLocalizations.of(context);
    final r = await showDialog<MemberRole>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.changeRole),
        children: [
          for (final role in MemberRole.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, role),
              child: ListTile(
                title: Text(roleLabel(l, role)),
                subtitle: Text(roleHint(l, role)),
                trailing: role == m.role ? const Icon(Icons.check) : null,
              ),
            ),
        ],
      ),
    );
    if (r == null || r == m.role) return;
    await ref.read(groupsRepositoryProvider).changeRole(spaceId, m.userId, r);
    ref.read(groupsVersionProvider.notifier).bump();
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, Member m) async {
    final l = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.removeConfirm(m.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.remove),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await ref.read(groupsRepositoryProvider).removeMember(spaceId, m.userId);
    ref.read(groupsVersionProvider.notifier).bump();
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, Space space) async {
    final l = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.leaveConfirm(space.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.leave),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await ref.read(groupsRepositoryProvider).leave(spaceId);
      ref.invalidate(mySpacesProvider);
      if (context.mounted) context.go('/spaces');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.errorGeneric)));
      }
    }
  }
}
