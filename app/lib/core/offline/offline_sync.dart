import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import 'local_store.dart';

/// True for failures that mean "no internet or no answer", as opposed to
/// the server saying no. Only these switch the app to saved data and
/// put changes in the waiting list.
bool isOfflineError(Object e) =>
    e is OfflineNoData ||
    e is SocketException ||
    e is TimeoutException ||
    e is HandshakeException ||
    e is http.ClientException ||
    e is sb.AuthRetryableFetchException ||
    (e is sb.PostgrestException &&
        e.code == null &&
        RegExp(
          r'SocketException|Failed host lookup|Connection (refused|reset|closed)',
        ).hasMatch(e.message));

/// Nothing saved on this phone yet for a screen, and no internet.
class OfflineNoData implements Exception {
  const OfflineNoData(this.key);
  final String key;
  @override
  String toString() => 'No saved data for $key and no internet';
}

/// A change made on this phone that has not reached the server yet.
class PendingChange {
  PendingChange({
    required this.id,
    required this.kind,
    required this.params,
    required this.createdAt,
    this.error,
  });

  final String id;

  /// What to do, for example 'ledger.addEntry'. Each kind has a sender.
  final String kind;
  final Map<String, dynamic> params;
  final DateTime createdAt;

  /// Set when the server refused it. It then waits for the person to try
  /// again or drop it, and is never retried on its own.
  String? error;
  bool get failed => error != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'params': params,
    'created_at': createdAt.toIso8601String(),
    'error': error,
  };

  static PendingChange fromJson(Map<String, dynamic> j) => PendingChange(
    id: j['id'] as String,
    kind: j['kind'] as String,
    params: Map<String, dynamic>.from(j['params'] as Map),
    createdAt: DateTime.parse(j['created_at'] as String),
    error: j['error'] as String?,
  );
}

/// Sends one kind of change to the server.
typedef ChangeSender = Future<void> Function(Map<String, dynamic> params);

/// Changes how saved data looks while a change is waiting, so the screen
/// shows what the person did. Returns the data, changed or not.
typedef ChangeOverlay = Object? Function(
  String key,
  Object? data,
  PendingChange change,
);

/// Decides whether a refusal means the change had already gone through
/// (for example a retry after the answer was lost).
typedef AlreadyDone = bool Function(Object error, PendingChange change);

/// The offline layer. Screens keep asking the repositories as before; the
/// repositories route reads and writes through here.
///
/// Reads: fresh data is saved on the phone. With no internet, or no answer
/// within a few seconds, the saved copy is used instead.
///
/// Writes: tried at once when online and nothing is waiting. Otherwise
/// they join the waiting list, which is sent in order when the internet is
/// back. Waiting changes are laid over the saved data so the screens show
/// them straight away.
class OfflineSync extends ChangeNotifier {
  OfflineSync({
    required this.store,
    this.slowAnswer = const Duration(seconds: 6),
    bool watchConnectivity = true,
  }) {
    if (watchConnectivity) _watch();
  }

  static const _queueKey = '_pending_changes';
  final LocalStore store;

  /// With saved data at hand, wait no longer than this for the server.
  final Duration slowAnswer;

  final _senders = <String, ChangeSender>{};
  final _overlays = <ChangeOverlay>[];
  final _alreadyDone = <String, AlreadyDone>{};
  final _onSent = <VoidCallback>[];
  List<PendingChange>? _queue;
  bool _offline = false;
  bool _flushing = false;
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  /// The last try found no internet. Shown as the "Offline" strip.
  bool get isOffline => _offline;

  List<PendingChange> get pending => List.unmodifiable(_queue ?? const []);
  int get waitingCount => (_queue ?? const []).where((c) => !c.failed).length;
  int get failedCount => (_queue ?? const []).where((c) => c.failed).length;

  void registerSender(String kind, ChangeSender send, {AlreadyDone? done}) {
    _senders[kind] = send;
    if (done != null) _alreadyDone[kind] = done;
  }

  void registerOverlay(ChangeOverlay overlay) {
    if (!_overlays.contains(overlay)) _overlays.add(overlay);
  }

  /// Called after changes reached the server, so screens reload.
  void onSent(VoidCallback f) => _onSent.add(f);

  Future<List<PendingChange>> _load() async {
    if (_queue != null) return _queue!;
    final raw = await store.read(_queueKey);
    _queue = [
      if (raw is List)
        for (final j in raw)
          PendingChange.fromJson(Map<String, dynamic>.from(j as Map)),
    ];
    return _queue!;
  }

  Future<void> _save() =>
      store.write(_queueKey, [for (final c in _queue!) c.toJson()]);

  void _setOffline(bool v) {
    if (_offline == v) return;
    _offline = v;
    notifyListeners();
    if (!v) unawaited(flush());
  }

  /// Loads the pending list from the phone. Call once at start.
  Future<void> start() async {
    await _load();
    notifyListeners();
    if (_queue!.any((c) => !c.failed)) unawaited(flush());
  }

  void _watch() {
    try {
      _connSub = Connectivity().onConnectivityChanged.listen((r) {
        final none = r.every((x) => x == ConnectivityResult.none);
        if (none) {
          _setOffline(true);
        } else {
          // A network is there; whether the internet works shows on the
          // next request. Try sending what is waiting.
          unawaited(flush());
        }
      }, onError: (_) {});
    } catch (_) {
      // Not available here (tests, some platforms).
    }
  }

  /// Saved-first read. [fetch] asks the server and returns plain JSON.
  Future<Object?> read(String key, Future<Object?> Function() fetch) async {
    final queue = await _load();
    Object? data;
    Object? saved = await store.read(key);
    try {
      final f = fetch();
      // Known offline: give the server 2 seconds, then use what the phone
      // has, even when that is nothing saved (overlays may still fill it).
      data = _offline
          ? await f.timeout(const Duration(seconds: 2))
          : await (saved == null ? f : f.timeout(slowAnswer));
      await store.write(key, data);
      _setOffline(false);
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      _setOffline(true);
      data = saved;
    }
    for (final c in queue.where((c) => !c.failed)) {
      for (final o in _overlays) {
        data = o(key, data, c);
      }
    }
    // Nothing saved and nothing made on this phone for this screen.
    if (data == null && saved == null && _offline) throw OfflineNoData(key);
    return data;
  }

  /// Saved data only, with waiting changes laid over it. For building the
  /// answer to a change made offline.
  Future<Object?> saved(String key) async {
    final queue = await _load();
    Object? data = await store.read(key);
    for (final c in queue.where((c) => !c.failed)) {
      for (final o in _overlays) {
        data = o(key, data, c);
      }
    }
    return data;
  }

  /// A change. Sent now when possible, otherwise kept and sent later.
  /// [now] does it online and returns the real answer; [later] builds the
  /// answer shown while the change waits.
  Future<R> write<R>({
    required String kind,
    required Map<String, dynamic> params,
    required Future<R> Function() now,
    required FutureOr<R> Function() later,
  }) async {
    final queue = await _load();
    // Keep order: if anything is waiting, this waits behind it.
    if (!_offline && !queue.any((c) => !c.failed)) {
      try {
        final r = await now();
        _setOffline(false);
        return r;
      } catch (e) {
        if (!isOfflineError(e)) rethrow;
        _setOffline(true);
      }
    }
    queue.add(
      PendingChange(
        id: const Uuid().v4(),
        kind: kind,
        params: params,
        createdAt: DateTime.now(),
      ),
    );
    await _save();
    notifyListeners();
    _schedule();
    return await later();
  }

  void _schedule() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if ((_queue ?? const []).every((c) => c.failed)) {
        _timer?.cancel();
        _timer = null;
        return;
      }
      unawaited(flush());
    });
  }

  /// Sends what is waiting, oldest first. Stops at the first sign of no
  /// internet. A refused change is marked and kept; the rest carry on.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    var sent = 0;
    try {
      final queue = await _load();
      for (final c in List.of(queue)) {
        if (c.failed) continue;
        final send = _senders[c.kind];
        if (send == null) continue; // sender not ready yet
        try {
          await send(c.params);
          queue.remove(c);
          sent++;
          _setOffline(false);
        } catch (e) {
          if (isOfflineError(e)) {
            _setOffline(true);
            break;
          }
          if (_alreadyDone[c.kind]?.call(e, c) ?? false) {
            queue.remove(c);
            sent++;
          } else {
            c.error = _short(e);
          }
        }
        await _save();
      }
    } finally {
      _flushing = false;
      notifyListeners();
      if (sent > 0) {
        for (final f in _onSent) {
          f();
        }
      }
    }
  }

  static String _short(Object e) {
    final s = e is sb.PostgrestException ? e.message : '$e';
    return s.length > 300 ? s.substring(0, 300) : s;
  }

  /// Try a refused change again.
  Future<void> retry(String id) async {
    final queue = await _load();
    for (final c in queue) {
      if (c.id == id) c.error = null;
    }
    await _save();
    notifyListeners();
    await flush();
  }

  /// Drop a change that will not be sent.
  Future<void> discard(String id) async {
    final queue = await _load();
    queue.removeWhere((c) => c.id == id);
    await _save();
    notifyListeners();
    for (final f in _onSent) {
      f();
    }
  }

  /// Sign out: forget saved data and anything waiting.
  Future<void> clearAll() async {
    _queue = [];
    await store.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}

/// Replaced in main() with one backed by files on the phone.
final offlineSyncProvider = ChangeNotifierProvider<OfflineSync>(
  (ref) => OfflineSync(store: MemoryLocalStore(), watchConnectivity: false),
);

/// Server rows as a list of maps, whether fresh or from the phone.
List<Map<String, dynamic>> offlineRows(Object? data) => [
  for (final r in (data as List? ?? const []))
    Map<String, dynamic>.from(r as Map),
];

/// A retry of an insert that had already gone through: same id again.
bool isDuplicateKey(Object e, PendingChange c) =>
    e is sb.PostgrestException && e.code == '23505';

/// One server row as a map, or null, whether fresh or from the phone.
Map<String, dynamic>? offlineRow(Object? data) =>
    data == null ? null : Map<String, dynamic>.from(data as Map);
