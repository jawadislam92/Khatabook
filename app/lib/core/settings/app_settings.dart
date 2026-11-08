import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non secret preferences. Secrets (PIN hash) live in secure storage instead.
class AppSettings {
  const AppSettings({
    this.onboardingDone = false,
    this.languageCode = 'en',
    this.simpleMode = false,
    this.biometricEnabled = false,
    this.autoLockSeconds = 60,
  });

  final bool onboardingDone;
  final String languageCode;
  final bool simpleMode;
  final bool biometricEnabled;

  /// 0 locks as soon as the app goes to the background, -1 never locks.
  final int autoLockSeconds;

  Locale get locale => Locale(languageCode);

  AppSettings copyWith({
    bool? onboardingDone,
    String? languageCode,
    bool? simpleMode,
    bool? biometricEnabled,
    int? autoLockSeconds,
  }) {
    return AppSettings(
      onboardingDone: onboardingDone ?? this.onboardingDone,
      languageCode: languageCode ?? this.languageCode,
      simpleMode: simpleMode ?? this.simpleMode,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
    );
  }
}

/// Provided from main() after SharedPreferences has loaded.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in ProviderScope'),
);

class AppSettingsNotifier extends Notifier<AppSettings> {
  static const _kOnboarding = 'onboarding_done';
  static const _kLanguage = 'language';
  static const _kSimple = 'simple_mode';
  static const _kBiometric = 'biometric';
  static const _kAutoLock = 'auto_lock_seconds';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final p = _prefs;
    return AppSettings(
      onboardingDone: p.getBool(_kOnboarding) ?? false,
      languageCode: p.getString(_kLanguage) ?? 'en',
      simpleMode: p.getBool(_kSimple) ?? false,
      biometricEnabled: p.getBool(_kBiometric) ?? false,
      autoLockSeconds: p.getInt(_kAutoLock) ?? 60,
    );
  }

  Future<void> setOnboardingDone() async {
    state = state.copyWith(onboardingDone: true);
    await _prefs.setBool(_kOnboarding, true);
  }

  Future<void> setLanguage(String code) async {
    state = state.copyWith(languageCode: code);
    await _prefs.setString(_kLanguage, code);
  }

  Future<void> setSimpleMode(bool on) async {
    state = state.copyWith(simpleMode: on);
    await _prefs.setBool(_kSimple, on);
  }

  Future<void> setBiometric(bool on) async {
    state = state.copyWith(biometricEnabled: on);
    await _prefs.setBool(_kBiometric, on);
  }

  Future<void> setAutoLock(int seconds) async {
    state = state.copyWith(autoLockSeconds: seconds);
    await _prefs.setInt(_kAutoLock, seconds);
  }

  /// Called on sign out. Keeps language and display choices, drops security ones.
  Future<void> resetSecurity() async {
    state = state.copyWith(biometricEnabled: false);
    await _prefs.setBool(_kBiometric, false);
  }
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
