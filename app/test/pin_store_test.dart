import 'package:flutter_test/flutter_test.dart';
import 'package:khatabook/core/security/pin_store.dart';
import 'package:khatabook/core/security/secure_store.dart';

void main() {
  late MemorySecureStore store;
  late DateTime now;
  late PinStore pins;

  setUp(() {
    store = MemorySecureStore();
    now = DateTime(2026, 11, 8, 10);
    // Few iterations keep the test fast; production uses 20000.
    pins = PinStore(store, clock: () => now, iterations: 50);
  });

  test('starts unset, then set', () async {
    expect(await pins.isSet, isFalse);
    await pins.setPin('1234');
    expect(await pins.isSet, isTrue);
  });

  test('never stores the PIN itself', () async {
    await pins.setPin('1234');
    final values = [await store.read('pin_salt'), await store.read('pin_hash')];
    for (final v in values) {
      expect(v, isNotNull);
      expect(v, isNot(contains('1234')));
    }
  });

  test('verifies the right PIN and rejects a wrong one', () async {
    await pins.setPin('2580');
    expect(await pins.verify('2580'), PinResult.ok);
    expect(await pins.verify('2581'), PinResult.wrong);
    expect(await pins.verify('258'), PinResult.wrong);
  });

  test('same PIN gives different hashes on each set (random salt)', () async {
    await pins.setPin('1234');
    final a = await store.read('pin_hash');
    await pins.setPin('1234');
    final b = await store.read('pin_hash');
    expect(a, isNot(b));
  });

  test(
    'locks out after five wrong tries and recovers after the wait',
    () async {
      await pins.setPin('1234');
      for (var i = 0; i < 4; i++) {
        expect(await pins.verify('0000'), PinResult.wrong);
      }
      expect(await pins.verify('0000'), PinResult.lockedOut);
      expect(await pins.lockoutSecondsLeft(), 30);
      // Even the right PIN is refused during the lockout.
      expect(await pins.verify('1234'), PinResult.lockedOut);
      now = now.add(const Duration(seconds: 31));
      expect(await pins.lockoutSecondsLeft(), 0);
      expect(await pins.verify('1234'), PinResult.ok);
      expect(await pins.failedAttempts(), 0);
    },
  );

  test('a correct PIN resets the failure count', () async {
    await pins.setPin('1234');
    await pins.verify('0000');
    await pins.verify('0000');
    expect(await pins.failedAttempts(), 2);
    await pins.verify('1234');
    expect(await pins.failedAttempts(), 0);
  });

  test('clear removes everything', () async {
    await pins.setPin('1234');
    await pins.clear();
    expect(await pins.isSet, isFalse);
    expect(await pins.verify('1234'), PinResult.wrong);
  });

  test('derive is deterministic for the same inputs', () {
    final salt = List<int>.generate(16, (i) => i);
    expect(
      PinStore.derive('1234', salt, 10),
      PinStore.derive('1234', salt, 10),
    );
    expect(
      PinStore.derive('1234', salt, 10),
      isNot(PinStore.derive('1235', salt, 10)),
    );
  });
}
