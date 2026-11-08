import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/security/app_lock.dart';
import '../../core/security/pin_store.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/brand_header.dart';
import '../../core/widgets/number_pad.dart';
import '../../core/widgets/pin_dots.dart';
import '../../l10n/app_localizations.dart';

/// Pick a PIN, confirm it, then offer biometrics. Used at first sign in and
/// from Settings to change the PIN.
class SetPinScreen extends ConsumerStatefulWidget {
  const SetPinScreen({super.key, this.onDone});

  /// Called after the PIN is saved. When null the router takes over.
  final VoidCallback? onDone;

  @override
  ConsumerState<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends ConsumerState<SetPinScreen> {
  String _first = '';
  String _current = '';
  bool _confirming = false;
  String? _error;

  Future<void> _digit(String d) async {
    if (_current.length >= 6) return;
    setState(() {
      _current += d;
      _error = null;
    });
  }

  void _back() {
    if (_current.isEmpty) return;
    setState(() => _current = _current.substring(0, _current.length - 1));
  }

  Future<void> _next() async {
    final l = AppLocalizations.of(context);
    if (_current.length < 4) {
      setState(() => _error = l.pinTooShort);
      return;
    }
    if (!_confirming) {
      setState(() {
        _first = _current;
        _current = '';
        _confirming = true;
      });
      return;
    }
    if (_current != _first) {
      setState(() {
        _error = l.pinMismatch;
        _first = '';
        _current = '';
        _confirming = false;
      });
      return;
    }
    await ref.read(pinStoreProvider).setPin(_current);
    await ref.read(appLockProvider.notifier).pinWasSet();
    if (!mounted) return;
    await _offerBiometrics();
    if (!mounted) return;
    widget.onDone?.call();
  }

  Future<void> _offerBiometrics() async {
    final l = AppLocalizations.of(context);
    final settings = ref.read(appSettingsProvider.notifier);
    bool available = false;
    try {
      final auth = LocalAuthentication();
      available =
          await auth.canCheckBiometrics || await auth.isDeviceSupported();
    } catch (_) {
      available = false;
    }
    if (!available || !mounted) return;
    final turnOn = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.biometricAskTitle),
        content: Text(l.biometricAskBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.notNow),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.turnOn),
          ),
        ],
      ),
    );
    if (turnOn == true) await settings.setBiometric(true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: widget.onDone == null ? null : AppBar(),
      body: Column(
        children: [
          BrandHeader(
            title: _confirming ? l.confirmPinTitle : l.setPinTitle,
            subtitle: _confirming ? l.confirmPinBody : l.setPinBody,
            gradient: Tokens.violetGradient,
            icon: Icons.pin_rounded,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(Tokens.s4),
              child: Column(
                children: [
                  const SizedBox(height: Tokens.s5),
                  PinDots(filled: _current.length, error: _error != null),
                  const SizedBox(height: Tokens.s3),
                  SizedBox(
                    height: 48,
                    child: _error == null
                        ? null
                        : Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: text.bodyLarge?.copyWith(
                              color: scheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const Spacer(),
                  NumberPad(onDigit: _digit, onBackspace: _back),
                  const SizedBox(height: Tokens.s4),
                  FilledButton(
                    onPressed: _current.length >= 4 ? _next : null,
                    child: Text(l.continueLabel),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
