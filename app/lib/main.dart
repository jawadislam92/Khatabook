import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/errors/error_reporter.dart';
import 'core/net/timeout_client.dart';
import 'core/settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  ErrorReporter? reporter;
  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
      httpClient: TimeoutClient(),
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    // Local test login (web on this computer only, see AppConfig).
    if (AppConfig.devAutoSignIn) {
      if (!prefs.containsKey('onboarding_done')) {
        await prefs.setBool('onboarding_done', true);
      }
      final auth = Supabase.instance.client.auth;
      if (auth.currentUser == null) {
        try {
          await auth.signInWithPassword(
            email: AppConfig.devAutoEmail,
            password: AppConfig.devAutoPassword,
          );
        } catch (e) {
          // Wrong or old password: the normal sign in screen shows.
          debugPrint('Local test login failed: $e');
        }
      }
    }
    // Debug runs stay out of the table; their errors are on the console.
    if (!kDebugMode) {
      final client = Supabase.instance.client;
      reporter = ErrorReporter(
        send: (row) => client.from('client_errors').insert(row),
        signedIn: () => client.auth.currentUser != null,
        appVersion: AppConfig.appVersion,
        platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
      )..install();
    }
  }
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        errorReporterProvider.overrideWithValue(reporter),
      ],
      observers: [if (reporter != null) ErrorReportingObserver(reporter)],
      retry: reporter?.retryAndReport,
      child: const DuebookApp(),
    ),
  );
}
