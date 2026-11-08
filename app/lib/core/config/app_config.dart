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
  static const authRedirect = 'com.sparkingissue.duebook://login-callback';

  /// True when a real backend is configured. Otherwise the app runs in
  /// preview mode with in memory data, which is what the web preview uses.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.1.0',
  );
}
