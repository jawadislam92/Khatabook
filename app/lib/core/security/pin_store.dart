import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'secure_store.dart';

/// Result of a PIN check.
enum PinResult { ok, wrong, lockedOut }

/// Stores a salted, stretched hash of the PIN in secure storage and limits
/// how fast someone can guess. The PIN itself is never stored.
class PinStore {
  PinStore(this._store, {DateTime Function()? clock, this.iterations = 20000})
    : _clock = clock ?? DateTime.now;

  final SecureStore _store;
  final DateTime Function() _clock;
  final int iterations;

  static const _kSalt = 'pin_salt';
  static const _kHash = 'pin_hash';
  static const _kFails = 'pin_fails';
  static const _kLockUntil = 'pin_lock_until';

  static const maxAttemptsBeforeLock = 5;
  static const lockDuration = Duration(seconds: 30);

  Future<bool> get isSet async => (await _store.read(_kHash)) != null;

  Future<void> setPin(String pin) async {
    assert(pin.length >= 4);
    final salt = _randomBytes(16);
    final hash = derive(pin, salt, iterations);
    await _store.write(_kSalt, base64Encode(salt));
    await _store.write(_kHash, base64Encode(hash));
    await _store.delete(_kFails);
    await _store.delete(_kLockUntil);
  }

  Future<void> clear() async {
    for (final k in [_kSalt, _kHash, _kFails, _kLockUntil]) {
      await _store.delete(k);
    }
  }

  /// Seconds left in a lockout, or 0 when checks are allowed.
  Future<int> lockoutSecondsLeft() async {
    final until = await _store.read(_kLockUntil);
    if (until == null) return 0;
    final t = DateTime.tryParse(until);
    if (t == null) return 0;
    final left = t.difference(_clock()).inSeconds;
    return left > 0 ? left : 0;
  }

  Future<int> failedAttempts() async =>
      int.tryParse(await _store.read(_kFails) ?? '0') ?? 0;

  Future<PinResult> verify(String pin) async {
    if (await lockoutSecondsLeft() > 0) return PinResult.lockedOut;
    final saltText = await _store.read(_kSalt);
    final hashText = await _store.read(_kHash);
    if (saltText == null || hashText == null) return PinResult.wrong;
    final expected = base64Decode(hashText);
    final actual = derive(pin, base64Decode(saltText), iterations);
    if (_constantTimeEquals(expected, actual)) {
      await _store.delete(_kFails);
      await _store.delete(_kLockUntil);
      return PinResult.ok;
    }
    final fails = (await failedAttempts()) + 1;
    await _store.write(_kFails, '$fails');
    if (fails >= maxAttemptsBeforeLock) {
      await _store.write(
        _kLockUntil,
        _clock().add(lockDuration).toIso8601String(),
      );
      await _store.write(_kFails, '0');
      return PinResult.lockedOut;
    }
    return PinResult.wrong;
  }

  /// PBKDF2 with HMAC SHA256. Small input space (digits), so stretching matters.
  static Uint8List derive(String pin, List<int> salt, int iterations) {
    final mac = Hmac(sha256, utf8.encode(pin));
    final block = Uint8List.fromList([...salt, 0, 0, 0, 1]);
    var u = Uint8List.fromList(mac.convert(block).bytes);
    final out = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(mac.convert(u).bytes);
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return out;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }
}

final secureStoreProvider = Provider<SecureStore>(
  (ref) => PlatformSecureStore(),
);
final pinStoreProvider = Provider<PinStore>(
  (ref) => PinStore(ref.watch(secureStoreProvider)),
);
