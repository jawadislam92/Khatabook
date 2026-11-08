import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/screen_scaffold.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_repository.dart';
import 'spaces_repository.dart';

class SpacesScreen extends ConsumerWidget {
  const SpacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final spaces = ref.watch(mySpacesProvider);
    final live = ref.watch(authRepositoryProvider).isLive;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ScreenScaffold(
      title: l.spaces,
      actions: [
        IconButton(
          tooltip: l.settings,
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.push('/settings'),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createGroup(context, ref),
        icon: const Icon(Icons.group_add_outlined),
        label: Text(l.newGroup),
      ),
      children: [
        if (!live)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s3),
            child: Text(
              l.demoBanner,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        spaces.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Tokens.s6),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Column(
            children: [
              Text(l.errorGeneric),
              const SizedBox(height: Tokens.s3),
              OutlinedButton(
                onPressed: () => ref.invalidate(mySpacesProvider),
                child: Text(l.retry),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(Tokens.s5),
                  child: Text(
                    l.emptySpaces,
                    textAlign: TextAlign.center,
                    style: text.bodyLarge,
                  ),
                )
              : Column(
                  children: [
                    for (final s in list) ...[
                      _SpaceTile(space: s),
                      const SizedBox(height: Tokens.s3),
                    ],
                    const SizedBox(height: Tokens.s7),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    var business = false;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l.newGroupTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l.groupName,
                  helperText: l.newGroupHint,
                ),
              ),
              const SizedBox(height: Tokens.s3),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.thisIsBusiness),
                subtitle: Text(l.thisIsBusinessHint),
                value: business,
                onChanged: (v) => setState(() => business = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, controller.text.trim().isNotEmpty),
              child: Text(l.create),
            ),
          ],
        ),
      ),
    );
    if (created == true) {
      await ref
          .read(spacesRepositoryProvider)
          .createGroup(controller.text, business: business);
      ref.invalidate(mySpacesProvider);
    }
    controller.dispose();
  }
}

class _SpaceTile extends StatelessWidget {
  const _SpaceTile({required this.space});
  final Space space;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final (icon, kindLabel) = switch ((space.kind, space.businessEnabled)) {
      (SpaceKind.personal, _) => (Icons.person_outline, l.spaceKindPersonal),
      (SpaceKind.group, true) => (
        Icons.storefront_outlined,
        l.spaceKindBusiness,
      ),
      (SpaceKind.group, false) => (
        Icons.family_restroom_outlined,
        l.spaceKindFamily,
      ),
    };
    final name = space.kind == SpaceKind.personal
        ? l.spacePersonal
        : space.name;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Tokens.radius),
        onTap: () => ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l.comingSoon))),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s4),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
                child: Icon(icon, color: scheme.primary, size: 28),
              ),
              const SizedBox(width: Tokens.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      space.kind == SpaceKind.personal
                          ? kindLabel
                          : '$kindLabel  ·  ${l.membersCount(space.memberCount)}',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
