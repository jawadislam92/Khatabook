import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/jobs/jobs_repository.dart';
import '../config/app_config.dart';
import '../router/app_router.dart';

/// Registers this phone for push alerts when the build has Firebase configured
/// (google-services.json present and --dart-define=FIREBASE_ENABLED=true).
/// Without that, this does nothing and alerts still appear in the in app inbox.
class PushService {
  PushService(this._ref);
  final Ref _ref;
  bool _started = false;

  Future<void> start() async {
    if (_started || !AppConfig.pushEnabled || kIsWeb) return;
    _started = true;
    try {
      await Firebase.initializeApp();
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(alert: true, badge: true, sound: true);
      final token = await fm.getToken();
      if (token != null) await _register(token);
      fm.onTokenRefresh.listen(_register);
      // A tap on a notification opens the job it is about.
      FirebaseMessaging.onMessageOpenedApp.listen(_open);
      final initial = await fm.getInitialMessage();
      if (initial != null) _open(initial);
    } catch (e) {
      debugPrint('push registration skipped: $e');
    }
  }

  Future<void> _register(String token) => _ref
      .read(jobsRepositoryProvider)
      .registerDevice(token, Platform.isIOS ? 'ios' : 'android');

  void _open(RemoteMessage m) {
    final link = m.data['link'];
    if (link is String && link.startsWith('/')) {
      _ref.read(routerProvider).push(link);
    }
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));
