import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(0, Tokens.s5, 0, Tokens.s2),
      child: Text(
        title.toUpperCase(),
        style: text.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
          letterSpacing: 1,
        ),
      ),
    );

    return ScreenScaffold(
      title: l.settings,
      children: [
        section(l.settingsDisplay),
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
              ListTile(
                title: Text(l.settingsLanguage),
                trailing: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'en', label: Text(l.languageEnglish)),
                    ButtonSegment(value: 'ur', label: Text(l.languageUrdu)),
                  ],
                  selected: {s.languageCode},
                  onSelectionChanged: (v) => n.setLanguage(v.first),
                ),
              ),
            ],
          ),
        ),
        section(l.settingsSecurity),
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
        section(l.settingsAccount),
        Card(
          child: ListTile(
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text(l.signOut, style: TextStyle(color: scheme.error)),
            subtitle: Text(ref.watch(currentUserProvider).value?.email ?? ''),
            onTap: () => _signOut(context, ref),
          ),
        ),
        section(l.settingsAbout),
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
        content: Text(l.signOutConfirm),
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
  }
}
