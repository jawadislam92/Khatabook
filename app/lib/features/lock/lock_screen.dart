import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/security/app_lock.dart';
import '../../core/security/pin_store.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/number_pad.dart';
import '../../core/widgets/pin_dots.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_repository.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _pin = '';
  String? _error;
  int _lockLeft = 0;
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _refreshLockout();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(appSettingsProvider).biometricEnabled) _biometric();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLockout() async {
    final left = await ref.read(pinStoreProvider).lockoutSecondsLeft();
    if (!mounted) return;
    setState(() => _lockLeft = left);
    _timer?.cancel();
    if (left > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _lockLeft = (_lockLeft - 1).clamp(0, 9999);
          if (_lockLeft == 0) {
            _timer?.cancel();
            _error = null;
          }
        });
      });
    }
  }

  Future<void> _digit(String d) async {
    if (_lockLeft > 0 || _checking || _pin.length >= 6) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length >= 4) await _tryUnlock();
  }

  Future<void> _tryUnlock() async {
    // Give 6 digit PINs a moment to finish typing: verify at 4+ only after a pause.
    final snapshot = _pin;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted || _pin != snapshot) return;
    setState(() => _checking = true);
    final store = ref.read(pinStoreProvider);
    final result = await store.verify(_pin);
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    switch (result) {
      case PinResult.ok:
        ref.read(appLockProvider.notifier).unlock();
      case PinResult.wrong:
        final fails = await store.failedAttempts();
        setState(() {
          _pin = '';
          _error = l.wrongPin(PinStore.maxAttemptsBeforeLock - fails);
        });
      case PinResult.lockedOut:
        setState(() => _pin = '');
        await _refreshLockout();
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _biometric() async {
    final l = AppLocalizations.of(context);
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: l.biometricReason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (ok && mounted) ref.read(appLockProvider.notifier).unlock();
    } catch (_) {
      // Fall back to the PIN silently.
    }
  }

  Future<void> _forgot() async {
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final biometric = ref.watch(appSettingsProvider).biometricEnabled;
    final message = _lockLeft > 0 ? l.lockedOut(_lockLeft) : _error;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s4),
          child: Column(
            children: [
              const Spacer(),
              Icon(Icons.lock_outline, size: 48, color: scheme.primary),
              const SizedBox(height: Tokens.s3),
              Text(
                l.enterPin,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Tokens.s5),
              PinDots(filled: _pin.length, error: message != null),
              const SizedBox(height: Tokens.s3),
              SizedBox(
                height: 56,
                child: message == null
                    ? null
                    : Text(
                        message,
                        textAlign: TextAlign.center,
                        style: text.bodyLarge?.copyWith(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              const Spacer(),
              NumberPad(
                onDigit: _digit,
                onBackspace: () {
                  if (_pin.isEmpty) return;
                  setState(() => _pin = _pin.substring(0, _pin.length - 1));
                },
                trailing: biometric
                    ? Semantics(
                        button: true,
                        label: l.useFingerprint,
                        child: InkResponse(
                          onTap: _biometric,
                          radius: 40,
                          child: Icon(
                            Icons.fingerprint,
                            size: 36,
                            color: scheme.primary,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: Tokens.s3),
              TextButton(onPressed: _forgot, child: Text(l.forgotPin)),
            ],
          ),
        ),
      ),
    );
  }
}
