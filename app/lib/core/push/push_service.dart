import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/jobs/jobs_repository.dart';
import '../config/app_config.dart';

/// Registers this phone for push alerts when the build has Firebase configured.
/// Without the Firebase config (preview builds, CI) this does nothing, and alerts
/// still appear in the in app inbox. The firebase_messaging call is filled in
/// once google-services.json exists, behind the FIREBASE_ENABLED define.
class PushService {
  PushService(this._ref);
  final Ref _ref;
  bool _started = false;

  Future<void> start() async {
    if (_started || !AppConfig.pushEnabled || kIsWeb) return;
    _started = true;
    try {
      final token = await _obtainToken();
      if (token != null) {
        await _ref
            .read(jobsRepositoryProvider)
            .registerDevice(token, Platform.isIOS ? 'ios' : 'android');
      }
    } catch (e) {
      debugPrint('push registration skipped: $e');
    }
  }

  Future<String?> _obtainToken() async => null;
}

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));
