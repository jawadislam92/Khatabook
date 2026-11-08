import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/settings/app_settings.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/tokens.dart';
import 'l10n/app_localizations.dart';

class DuebookApp extends ConsumerWidget {
  const DuebookApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final router = ref.watch(routerProvider);
    final locale = settings.locale;

    return MaterialApp.router(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
      routerConfig: router,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.build(
        brightness: Brightness.light,
        simpleMode: settings.simpleMode,
        locale: locale,
      ),
      darkTheme: AppTheme.build(
        brightness: Brightness.dark,
        simpleMode: settings.simpleMode,
        locale: locale,
      ),
      builder: (context, child) {
        // Simple mode scales text on top of whatever the phone already does,
        // and caps the total so layouts stay usable.
        final mq = MediaQuery.of(context);
        final system = mq.textScaler.scale(1);
        final factor = settings.simpleMode
            ? system * Tokens.simpleTextScale
            : system;
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(factor.clamp(0.8, 2.0)),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
