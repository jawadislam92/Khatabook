import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../../features/jobs/jobs_repository.dart';
import '../../l10n/app_localizations.dart';
import '../config/app_config.dart';
import '../router/app_router.dart';

/// Whether alerts reach this phone.
enum PushStatus {
  /// Not known yet, or this build has no push (web, preview).
  unknown,
  on,

  /// The phone does not let Duebook show alerts.
  off,

  /// Alerts are allowed but this phone could not be registered.
  failed,
}

final pushStatusProvider = StateProvider<PushStatus>((_) => PushStatus.unknown);

/// For the message shown when an alert arrives while the app is open.
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Registers this phone for push alerts when the build has Firebase configured
/// (google-services.json present and --dart-define=FIREBASE_ENABLED=true).
/// Without that, this does nothing and alerts still appear in the in app inbox.
class PushService {
  PushService(this._ref);
  final Ref _ref;
  Future<void>? _ready;
  String? _token;
  String? _userId;
  bool _registered = false;
  bool _working = false;

  static const _native = MethodChannel('duebook/alerts');

  bool get _can => AppConfig.pushEnabled && !kIsWeb;

  Future<void> _init() async {
    await Firebase.initializeApp();
    final fm = FirebaseMessaging.instance;
    fm.onTokenRefresh.listen((t) {
      _token = t;
      _registered = false;
      unawaited(check());
    });
    FirebaseMessaging.onMessage.listen(_showInApp);
    // A tap on a notification opens the job it is about.
    FirebaseMessaging.onMessageOpenedApp.listen(_open);
    final initial = await fm.getInitialMessage();
    if (initial != null) _open(initial);
  }

  /// Call whenever someone is signed in. Each person is registered, so a
  /// second person signing in on the same phone gets their own alerts.
  Future<void> start(String userId) async {
    if (!_can || userId == _userId) return;
    _userId = userId;
    _registered = false;
    await check(ask: true);
  }

  /// Looks at the permission again and registers if that has not worked
  /// yet. Also called each time the app comes back to the front.
  Future<void> check({bool ask = false}) async {
    if (!_can || _userId == null || _working) return;
    _working = true;
    try {
      await (_ready ??= _init());
      final fm = FirebaseMessaging.instance;
      final s = ask
          ? await fm.requestPermission(alert: true, badge: true, sound: true)
          : await fm.getNotificationSettings();
      final allowed =
          s.authorizationStatus == AuthorizationStatus.authorized ||
          s.authorizationStatus == AuthorizationStatus.provisional;
      // Registered even when off, so alerts work the moment they are allowed.
      while (!_registered && _userId != null) {
        final user = _userId;
        final token = _token ??= await fm.getToken().timeout(
          const Duration(seconds: 20),
        );
        if (token == null) throw StateError('no push token');
        await _ref
            .read(jobsRepositoryProvider)
            .registerDevice(token, Platform.isIOS ? 'ios' : 'android');
        _registered = user == _userId;
      }
      if (_userId != null) _set(allowed ? PushStatus.on : PushStatus.off);
    } catch (e) {
      debugPrint('push registration failed: $e');
      // A failed start must not stop the next try.
      if (Firebase.apps.isEmpty) _ready = null;
      if (_userId != null) _set(PushStatus.failed);
    } finally {
      _working = false;
    }
  }

  void _set(PushStatus s) => _ref.read(pushStatusProvider.notifier).state = s;

  /// The "Turn on" button. Android shows its question only twice; after
  /// that the phone's own settings page is the only way.
  Future<void> turnOn() async {
    await check(ask: true);
    if (_ref.read(pushStatusProvider) == PushStatus.off) {
      try {
        await _native.invokeMethod<void>('openSettings');
      } catch (e) {
        debugPrint('could not open settings: $e');
      }
    }
  }

  /// Before signing out: this phone stops getting this person's alerts.
  Future<void> signedOut() async {
    final token = _token;
    _userId = null;
    _registered = false;
    if (!_can) return;
    _set(PushStatus.unknown);
    if (token == null) return;
    try {
      await _ref
          .read(jobsRepositoryProvider)
          .unregisterDevice(token)
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('push sign out: $e');
    }
  }

  /// Android shows nothing by itself while the app is open.
  void _showInApp(RemoteMessage m) {
    _ref.invalidate(notificationsProvider);
    final n = m.notification;
    final messenger = appMessengerKey.currentState;
    if (n == null || messenger == null) return;
    unawaited(HapticFeedback.vibrate());
    unawaited(SystemSound.play(SystemSoundType.alert));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('${n.title ?? ''}\n${n.body ?? ''}'),
          action: SnackBarAction(
            label: AppLocalizations.of(messenger.context).openAlert,
            onPressed: () => _open(m),
          ),
        ),
      );
  }

  void _open(RemoteMessage m) {
    final link = m.data['link'];
    if (link is String && link.startsWith('/')) {
      _ref.read(alertLinkProvider).open(link);
    }
  }
}

/// Opens the job an alert is about. The PIN screen comes first when the app
/// is locked, so the link waits for it and opens right after.
class AlertLink {
  AlertLink(this._router) {
    _router.routerDelegate.addListener(_check);
  }
  final GoRouter _router;
  String? _waiting;
  String? _opened;
  DateTime? _openedAt;

  static const _gates = {'/onboarding', '/auth', '/set-pin', '/lock'};

  void open(String link) {
    _waiting = link;
    _check();
  }

  void _check() {
    final config = _router.routerDelegate.currentConfiguration;
    if (config.isEmpty) return;
    if (_gates.contains(config.uri.path)) {
      // The lock came up just after the job opened: open it again later.
      final at = _openedAt;
      if (_waiting == null &&
          at != null &&
          DateTime.now().difference(at) < const Duration(seconds: 5)) {
        _waiting = _opened;
      }
      _openedAt = null;
      return;
    }
    final link = _waiting;
    if (link == null) return;
    _waiting = null;
    _opened = link;
    _openedAt = DateTime.now();
    // Not while the router is still telling its listeners.
    Future.microtask(() => _router.push(link));
  }

  void dispose() => _router.routerDelegate.removeListener(_check);
}

final alertLinkProvider = Provider<AlertLink>((ref) {
  final a = AlertLink(ref.watch(routerProvider));
  ref.onDispose(a.dispose);
  return a;
});

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));
