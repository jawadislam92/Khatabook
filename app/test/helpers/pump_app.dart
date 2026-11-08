import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khatabook/core/security/pin_store.dart';
import 'package:khatabook/core/security/secure_store.dart';
import 'package:khatabook/core/settings/app_settings.dart';
import 'package:khatabook/core/theme/app_theme.dart';
import 'package:khatabook/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps a screen in the real theme, localisations and providers for tests.
Future<ProviderContainer> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  bool simpleMode = false,
  String language = 'en',
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'simple_mode': simpleMode,
    'language': language,
    ...prefs,
  });
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      secureStoreProvider.overrideWithValue(MemorySecureStore()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) {
          final s = ref.watch(appSettingsProvider);
          return MaterialApp(
            locale: s.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.build(
              brightness: Brightness.light,
              simpleMode: s.simpleMode,
              locale: s.locale,
            ),
            home: screen,
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}
