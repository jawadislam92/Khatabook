import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings.dart';
import 'pin_store.dart';

/// Whether the app is behind the lock screen right now.
class AppLockState {
  const AppLockState({required this.pinSet, required this.locked});

  final bool pinSet;
  final bool locked;

  AppLockState copyWith({bool? pinSet, bool? locked}) => AppLockState(
    pinSet: pinSet ?? this.pinSet,
    locked: locked ?? this.locked,
  );
}

class AppLockNotifier extends Notifier<AppLockState>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;

  @override
  AppLockState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));
    // Until secure storage answers we assume a PIN exists, so a cold start
    // shows the lock rather than flashing content.
    _refreshPinSet();
    return const AppLockState(pinSet: true, locked: true);
  }

  Future<void> _refreshPinSet() async {
    final set = await ref.read(pinStoreProvider).isSet;
    state = state.copyWith(pinSet: set, locked: set && state.locked);
  }

  void unlock() => state = state.copyWith(locked: false);

  void lock() {
    if (state.pinSet) state = state.copyWith(locked: true);
  }

  Future<void> pinWasSet() async {
    state = const AppLockState(pinSet: true, locked: false);
  }

  Future<void> pinWasCleared() async {
    state = const AppLockState(pinSet: false, locked: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final autoLock = ref.read(appSettingsProvider).autoLockSeconds;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
      if (autoLock == 0) lock();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since != null && autoLock > 0) {
        if (DateTime.now().difference(since).inSeconds >= autoLock) lock();
      }
    }
  }
}

final appLockProvider = NotifierProvider<AppLockNotifier, AppLockState>(
  AppLockNotifier.new,
);
