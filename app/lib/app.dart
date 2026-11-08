import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/settings/app_settings.dart';
import 'core/theme/app_theme.dart';
import 'core/push/push_service.dart';
import 'core/theme/tokens.dart';
import 'features/auth/auth_repository.dart';
import 'features/groups/groups_models.dart';
import 'l10n/app_localizations.dart';

class DuebookApp extends ConsumerStatefulWidget {
  const DuebookApp({super.key});

  @override
  ConsumerState<DuebookApp> createState() => _DuebookAppState();
}

class _DuebookAppState extends ConsumerState<DuebookApp> {
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    // Invite links open the join screen. Auth callbacks are handled by Supabase itself.
    try {
      final appLinks = AppLinks();
      _links = appLinks.uriLinkStream.listen(_onLink);
      appLinks.getInitialLink().then((u) => u == null ? null : _onLink(u));
    } catch (_) {
      // Not supported on this platform (tests, some desktops).
    }
  }

  void _onLink(Uri uri) {
    if (uri.host == InviteLink.host &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'join') {
      final token = InviteLink.parse(uri.toString());
      if (token != null) ref.read(routerProvider).push('/join?token=$token');
    }
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final router = ref.watch(routerProvider);
    ref.listen(currentUserProvider, (_, next) {
      if (next.value != null) ref.read(pushServiceProvider).start();
    });
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
