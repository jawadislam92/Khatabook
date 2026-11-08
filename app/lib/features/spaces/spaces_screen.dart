import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
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
    final user = ref.watch(currentUserProvider).value;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final today = DateFormat.yMMMMEEEEd(locale).format(DateTime.now());

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createGroup(context, ref),
        icon: const Icon(Icons.group_add_outlined),
        label: Text(l.newGroup),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _Hero(
              greeting: l.greeting(user?.displayName ?? ''),
              date: today,
              onSettings: () => context.push('/settings'),
              settingsLabel: l.settings,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s4,
              Tokens.s4,
              Tokens.s4,
              Tokens.s7 * 2,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (!live)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Tokens.s3),
                    child: Row(
                      children: [
                        Icon(
                          Icons.science_outlined,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: Tokens.s2),
                        Expanded(
                          child: Text(
                            l.demoBanner,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  l.spaces,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: Tokens.s3),
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
                          ],
                        ),
                ),
              ]),
            ),
          ),
        ],
      ),
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

class _Hero extends StatelessWidget {
  const _Hero({
    required this.greeting,
    required this.date,
    required this.onSettings,
    required this.settingsLabel,
  });
  final String greeting;
  final String date;
  final VoidCallback onSettings;
  final String settingsLabel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: const BoxDecoration(
        gradient: Tokens.heroGradient,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(Tokens.radiusLarge + 8),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.s5,
            Tokens.s3,
            Tokens.s3,
            Tokens.s6,
          ),
          child: Stack(
            children: [
              // Soft decorative circles so the band is not flat colour.
              PositionedDirectional(
                end: -30,
                top: -40,
                child: _Bubble(size: 150, opacity: 0.14),
              ),
              PositionedDirectional(
                end: 70,
                bottom: -60,
                child: _Bubble(size: 120, opacity: 0.10),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Icon(
                          Icons.menu_book_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: settingsLabel,
                        onPressed: onSettings,
                        icon: const Icon(
                          Icons.settings_outlined,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Tokens.s5),
                  Text(
                    greeting,
                    style: text.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: Tokens.s1),
                  Text(
                    date,
                    style: text.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.size, required this.opacity});
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: opacity),
    ),
  );
}

class _SpaceTile extends StatelessWidget {
  const _SpaceTile({required this.space});
  final Space space;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (icon, kindLabel, hue) = switch ((
      space.kind,
      space.businessEnabled,
    )) {
      (SpaceKind.personal, _) => (
        Icons.person_rounded,
        l.spaceKindPersonal,
        Tokens.personalHue,
      ),
      (SpaceKind.group, true) => (
        Icons.storefront_rounded,
        l.spaceKindBusiness,
        Tokens.businessHue,
      ),
      (SpaceKind.group, false) => (
        Icons.family_restroom_rounded,
        l.spaceKindFamily,
        Tokens.familyHue,
      ),
    };
    final name = space.kind == SpaceKind.personal
        ? l.spacePersonal
        : space.name;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.radius),
        boxShadow: [
          BoxShadow(
            color: hue.withValues(alpha: dark ? 0.0 : 0.16),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(Tokens.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(l.comingSoon))),
          child: Row(
            children: [
              Container(width: 8, height: 96, color: hue),
              const SizedBox(width: Tokens.s3),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: hue.withValues(alpha: dark ? 0.3 : 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: hue, size: 30),
              ),
              const SizedBox(width: Tokens.s4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: Tokens.s2,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _Chip(label: kindLabel, color: hue),
                          if (space.kind != SpaceKind.personal)
                            Text(
                              l.membersCount(space.memberCount),
                              style: text.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: Tokens.s3),
                child: Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.3 : 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: dark ? Colors.white : color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
