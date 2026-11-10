import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build time configuration. Values come from --dart-define so no secret or
/// environment detail lives in the source tree.
///
/// Example:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
class AppConfig {
  const AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Deep link the OAuth flow returns to. Must match the Android manifest and
  /// the Supabase auth redirect allow list.
  static const authRedirect = 'com.sparkingasia.duebook://login-callback';

  /// True when a real backend is configured. Otherwise the app runs in
  /// preview mode with in memory data, which is what the web preview uses.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Google one tap on the phone: the Web client ID of the Google OAuth
  /// client that Supabase uses (public, not a secret). Without it the app
  /// opens Google in the browser instead. iPhone also needs its own client.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  /// Set --dart-define=FIREBASE_ENABLED=true on builds that ship google-services.json.
  static const pushEnabled = bool.fromEnvironment('FIREBASE_ENABLED');

  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.1.0',
  );

  /// Test login for the web build on this computer only. Give both with
  /// --dart-define (from app/.env.qa) and the app signs in by itself and
  /// skips the welcome and PIN screens. Ignored on phones and on any web
  /// address other than localhost.
  static const devAutoEmail = String.fromEnvironment('DEV_AUTO_EMAIL');
  static const devAutoPassword = String.fromEnvironment('DEV_AUTO_PASSWORD');

  static bool get devAutoSignIn => devAutoSignInAllowed(
    isWeb: kIsWeb,
    host: Uri.base.host,
    email: devAutoEmail,
    password: devAutoPassword,
  );
}

/// The rule behind [AppConfig.devAutoSignIn], kept apart so tests can check it.
bool devAutoSignInAllowed({
  required bool isWeb,
  required String host,
  required String email,
  required String password,
}) =>
    isWeb &&
    email.isNotEmpty &&
    password.isNotEmpty &&
    const {'localhost', '127.0.0.1'}.contains(host);

/// True while the local test login is on. The router skips the PIN gates.
final devAutoSignInProvider = Provider<bool>((_) => AppConfig.devAutoSignIn);
