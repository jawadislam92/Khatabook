// The offline layer on its own: saved data when there is no internet,
// changes kept in order and sent when it is back, refusals kept visible.
import 'dart:async';
import 'dart:io';

import 'package:duebook/core/offline/local_store.dart';
import 'package:duebook/core/offline/offline_sync.dart';
import 'package:flutter_test/flutter_test.dart';

const _noNet = SocketException('Failed host lookup');

OfflineSync _sync(LocalStore store) => OfflineSync(
  store: store,
  slowAnswer: const Duration(milliseconds: 200),
  watchConnectivity: false,
);

void main() {
  test('fresh data is saved and shown again with no internet', () async {
    final s = _sync(MemoryLocalStore());
    expect(await s.read('jobs:b', () async => [1, 2]), [1, 2]);
    expect(s.isOffline, isFalse);
    expect(await s.read('jobs:b', () async => throw _noNet), [1, 2]);
    expect(s.isOffline, isTrue);
  });

  test('no saved copy and no internet is an error the screen can show', () {
    final s = _sync(MemoryLocalStore());
    expect(
      s.read('jobs:b', () async => throw _noNet),
      throwsA(isA<OfflineNoData>()),
    );
  });

  test(
    'a server that does not answer falls back to the saved copy fast',
    () async {
      final s = _sync(MemoryLocalStore());
      await s.read('k', () async => 'old');
      final hang = Completer<Object?>();
      final sw = Stopwatch()..start();
      expect(await s.read('k', () => hang.future), 'old');
      expect(sw.elapsedMilliseconds, lessThan(2000));
    },
  );

  test('a refusal from the server is not mistaken for no internet', () {
    final s = _sync(MemoryLocalStore());
    expect(
      s.read('k', () async => throw StateError('permission denied')),
      throwsA(isA<StateError>()),
    );
  });

  test('offline changes wait, show at once, and go out in order', () async {
    final store = MemoryLocalStore();
    final s = _sync(store);
    final sent = <String>[];
    var online = false;
    s.registerSender('add', (p) async {
      if (!online) throw _noNet;
      sent.add(p['name'] as String);
    });
    s.registerOverlay((key, data, c) {
      if (key != 'names' || c.kind != 'add') return data;
      return [...(data as List? ?? const []), c.params['name']];
    });
    await s.read('names', () async => ['Ali']);

    for (final n in ['Bilal', 'Sara']) {
      final r = await s.write<String>(
        kind: 'add',
        params: {'name': n},
        now: () async {
          if (!online) throw _noNet;
          sent.add(n);
          return 'sent';
        },
        later: () => 'waiting',
      );
      expect(r, 'waiting');
    }
    expect(s.waitingCount, 2);
    expect(await s.read('names', () async => throw _noNet), [
      'Ali',
      'Bilal',
      'Sara',
    ]);

    // A restart keeps them.
    final again = _sync(store);
    await again.start();
    expect(again.waitingCount, 2);

    online = true;
    await s.flush();
    expect(sent, ['Bilal', 'Sara']);
    expect(s.waitingCount, 0);
  });

  test('while something waits, a new change waits behind it', () async {
    final s = _sync(MemoryLocalStore());
    var online = false;
    final sent = <int>[];
    s.registerSender('n', (p) async {
      if (!online) throw _noNet;
      sent.add(p['v'] as int);
    });
    await s.write<void>(
      kind: 'n',
      params: {'v': 1},
      now: () async => throw _noNet,
      later: () {},
    );
    online = true;
    await s.write<void>(
      kind: 'n',
      params: {'v': 2},
      now: () async => sent.add(99),
      later: () {},
    );
    await s.flush();
    expect(sent, [1, 2], reason: 'never jumps the queue');
  });

  test(
    'a refused change is kept with the reason and the rest still go',
    () async {
      final s = _sync(MemoryLocalStore());
      final sent = <int>[];
      var online = false;
      s.registerSender('n', (p) async {
        if (!online) throw _noNet;
        if (p['v'] == 1) throw StateError('This job is already invoiced');
        sent.add(p['v'] as int);
      });
      for (final v in [1, 2]) {
        await s.write<void>(
          kind: 'n',
          params: {'v': v},
          now: () async => throw _noNet,
          later: () {},
        );
      }
      online = true;
      await s.flush();
      expect(sent, [2]);
      expect(s.failedCount, 1);
      expect(s.pending.single.error, contains('already invoiced'));
      await s.discard(s.pending.single.id);
      expect(s.pending, isEmpty);
    },
  );

  test(
    'a change that already went through is not reported as refused',
    () async {
      final s = _sync(MemoryLocalStore());
      var online = false;
      s.registerSender('n', (p) async {
        if (!online) throw _noNet;
        throw StateError('duplicate key');
      }, done: (e, c) => '$e'.contains('duplicate key'));
      await s.write<void>(
        kind: 'n',
        params: const {},
        now: () async => throw _noNet,
        later: () {},
      );
      online = true;
      await s.flush();
      expect(s.pending, isEmpty);
    },
  );

  test('sign out forgets saved data and waiting changes', () async {
    final s = _sync(MemoryLocalStore());
    await s.read('k', () async => 'x');
    await s.write<void>(
      kind: 'n',
      params: const {},
      now: () async => throw _noNet,
      later: () {},
    );
    await s.clearAll();
    expect(s.pending, isEmpty);
    expect(
      s.read('k', () async => throw _noNet),
      throwsA(isA<OfflineNoData>()),
    );
  });

  test(
    'offline, a screen with nothing saved never waits on a silent server',
    () async {
      final s = _sync(MemoryLocalStore());
      // The phone already knows it is offline.
      await expectLater(
        s.read('other', () async => throw _noNet),
        throwsA(isA<OfflineNoData>()),
      );
      final hang = Completer<Object?>();
      final sw = Stopwatch()..start();
      await expectLater(
        s.read('entries_party:p1', () => hang.future),
        throwsA(isA<OfflineNoData>()),
      );
      expect(sw.elapsedMilliseconds, lessThan(3000));
    },
  );

  test('a screen never opened online still shows changes made here', () async {
    final s = _sync(MemoryLocalStore());
    s.registerOverlay((key, data, c) {
      if (key != 'entries_party:p1') return data;
      return [...(data as List? ?? const []), c.params['id']];
    });
    await s.write<void>(
      kind: 'add',
      params: {'id': 'e1'},
      now: () async => throw _noNet,
      later: () {},
    );
    expect(await s.read('entries_party:p1', () async => throw _noNet), ['e1']);
    expect(
      s.read('entries_party:p2', () async => throw _noNet),
      throwsA(isA<OfflineNoData>()),
    );
  });

  test(
    'a change that needs data not saved yet waits instead of failing',
    () async {
      final s = _sync(MemoryLocalStore());
      var online = false;
      s.registerSender('add', (p) async {
        // Like an entry that first needs the book id from the server.
        await s.read(
          'book:b',
          () async => online ? {'id': 'bk'} : throw _noNet,
        );
      });
      await s.write<void>(
        kind: 'add',
        params: const {},
        now: () async => throw _noNet,
        later: () {},
      );
      await s.flush();
      expect(s.failedCount, 0, reason: 'still waiting, not refused');
      expect(s.waitingCount, 1);
      online = true;
      await s.flush();
      expect(s.pending, isEmpty);
    },
  );
}
