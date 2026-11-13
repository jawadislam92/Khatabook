import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/offline/offline_sync.dart';
import '../../core/config/app_config.dart';
import '../../core/security/app_lock.dart';
import '../../core/security/pin_store.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/screen_scaffold.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(appSettingsProvider);
    final n = ref.read(appSettingsProvider.notifier);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget section(String title, IconData icon, Color color) => Padding(
      padding: const EdgeInsets.fromLTRB(0, Tokens.s5, 0, Tokens.s2),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: Tokens.s3),
          Text(
            title,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );

    return ScreenScaffold(
      title: l.settings,
      children: [
        section(l.settingsDisplay, Icons.palette_rounded, Tokens.violet),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: Text(l.settingsSimpleMode),
                subtitle: Text(l.settingsSimpleModeHint),
                value: s.simpleMode,
                onChanged: n.setSimpleMode,
              ),
              const Divider(height: 1),
              // Buttons under the label, so they fit with big text too.
              ListTile(
                title: Text(l.settingsLanguage),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: Tokens.s2),
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'en',
                        label: Text(l.languageEnglish),
                      ),
                      ButtonSegment(value: 'ur', label: Text(l.languageUrdu)),
                    ],
                    selected: {s.languageCode},
                    onSelectionChanged: (v) => n.setLanguage(v.first),
                  ),
                ),
              ),
            ],
          ),
        ),
        section(l.settingsSecurity, Icons.shield_rounded, Tokens.primary),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: Text(l.settingsBiometric),
                value: s.biometricEnabled,
                onChanged: n.setBiometric,
              ),
              const Divider(height: 1),
              ListTile(
                title: Text(l.settingsAutoLock),
                trailing: DropdownButton<int>(
                  value: s.autoLockSeconds,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(
                      value: 0,
                      child: Text(l.autoLockImmediately),
                    ),
                    DropdownMenuItem(
                      value: 60,
                      child: Text(l.autoLockOneMinute),
                    ),
                    DropdownMenuItem(
                      value: 300,
                      child: Text(l.autoLockFiveMinutes),
                    ),
                    DropdownMenuItem(value: -1, child: Text(l.autoLockNever)),
                  ],
                  onChanged: (v) => v == null ? null : n.setAutoLock(v),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: Text(l.settingsChangePin),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/change-pin'),
              ),
            ],
          ),
        ),
        section(l.settingsAccount, Icons.person_rounded, Tokens.indigo),
        if (ref.watch(currentUserProvider).value?.isGuest ?? false) ...[
          const _ConnectGoogleCard(),
          const SizedBox(height: Tokens.s3),
        ],
        Card(
          child: ListTile(
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text(l.signOut, style: TextStyle(color: scheme.error)),
            subtitle: Text(ref.watch(currentUserProvider).value?.email ?? ''),
            onTap: () => _signOut(context, ref),
          ),
        ),
        section(l.settingsAbout, Icons.info_rounded, Tokens.saffronDeep),
        Text(
          l.version(AppConfig.appVersion),
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(
          [
            (ref.read(currentUserProvider).value?.isGuest ?? false)
                ? l.guestSignOutWarning
                : l.signOutConfirm,
            if (ref.read(offlineSyncProvider).pending.isNotEmpty)
              l.signOutPending(ref.read(offlineSyncProvider).pending.length),
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.signOut),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await ref.read(pinStoreProvider).clear();
    await ref.read(appSettingsProvider.notifier).resetSecurity();
    await ref.read(appLockProvider.notifier).pinWasCleared();
    await ref.read(authRepositoryProvider).signOut();
    // The next person on this phone must not see this person's saved data.
    await ref.read(offlineSyncProvider).clearAll();
  }
}

/// Shown to someone who joined with only a name: connect Google so the
/// login is not lost with the phone.
class _ConnectGoogleCard extends ConsumerStatefulWidget {
  const _ConnectGoogleCard();

  @override
  ConsumerState<_ConnectGoogleCard> createState() => _ConnectGoogleCardState();
}

class _ConnectGoogleCardState extends ConsumerState<_ConnectGoogleCard> {
  var _busy = false;

  Future<void> _connect() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).connectGoogle();
      messenger.showSnackBar(SnackBar(content: Text(l.googleConnected)));
    } on AuthFailure catch (f) {
      if (f.kind != AuthFailureKind.cancelled) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              f.kind == AuthFailureKind.googleInUse
                  ? l.errorGoogleInUse
                  : l.errorGeneric,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radius),
        side: const BorderSide(color: Tokens.saffronDeep, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Tokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.guestSafeTitle,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Tokens.s1),
            Text(l.guestSafeBody),
            const SizedBox(height: Tokens.s3),
            FilledButton.icon(
              onPressed: _busy ? null : _connect,
              icon: const Icon(Icons.g_mobiledata),
              label: Text(l.guestConnectGoogle),
            ),
          ],
        ),
      ),
    );
  }
}
