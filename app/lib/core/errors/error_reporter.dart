import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sends short reports of failures on the phone to the `client_errors`
/// table, so the cause can be read from the database instead of asked for
/// in a screenshot.
///
/// It is deliberately quiet: the same failure is sent once per app run, at
/// most [maxPerRun] reports leave the phone per run, nothing is sent while
/// signed out, and a report that cannot be sent is dropped.
class ErrorReporter {
  ErrorReporter({
    required this._send,
    required this._signedIn,
    required this.appVersion,
    required this.platform,
  });

  static const maxPerRun = 20;
  static const _maxMessage = 2000;
  static const _maxDetail = 8000;
  static const _maxScreen = 200;

  final Future<void> Function(Map<String, dynamic> row) _send;
  final bool Function() _signedIn;
  final String appVersion;
  final String platform;

  /// Tells which screen is open. Set by the app once the router exists.
  String? Function()? currentScreen;

  final _seen = <String>{};
  int _sent = 0;

  /// [source] is one of `flutter` (a widget or framework error), `platform`
  /// (an error nobody caught) or `provider` (a data request that failed).
  void report(String source, Object error, [StackTrace? stack]) {
    try {
      final message = _clip(error.toString().trim(), _maxMessage);
      if (message.isEmpty || !_signedIn()) return;
      if (_sent >= maxPerRun || !_seen.add('$source|$message')) return;
      _sent++;
      String? screen;
      try {
        screen = currentScreen?.call();
      } catch (_) {
        // The screen name is a nice extra; send the report without it.
      }
      final row = <String, dynamic>{
        'source': source,
        'message': message,
        'detail': stack == null ? null : _clip(stack.toString(), _maxDetail),
        'screen': screen == null ? null : _clip(screen, _maxScreen),
        'app_version': appVersion,
        'platform': platform,
      };
      unawaited(
        _send(row).catchError((Object e) {
          debugPrint('error report not sent: $e');
        }),
      );
    } catch (e) {
      // Reporting must never be the thing that breaks the app.
      debugPrint('error report not sent: $e');
    }
  }

  /// The retry rule for the app's providers: Riverpod's own, plus a report
  /// of the first failure.
  ///
  /// While Riverpod is still retrying a load in the background it does not
  /// tell [ErrorReportingObserver] about the failure, and with ten retries
  /// that can take minutes, so most failures were never reported. This rule
  /// sees every failure as it happens.
  Duration? retryAndReport(int retryCount, Object error) {
    if (retryCount == 0) report('provider', error);
    return ProviderContainer.defaultRetry(retryCount, error);
  }

  static String _clip(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);

  /// Hooks the reporter into Flutter. Whatever handled these errors before
  /// still runs afterwards.
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      report('flutter', details.exception, details.stack);
      previous?.call(details);
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      report('platform', error, stack);
      return previousPlatform?.call(error, stack) ?? false;
    };
  }
}

/// The reporter of this app run, or null in preview mode and debug runs.
final errorReporterProvider = Provider<ErrorReporter?>((ref) => null);

/// Reports a data request that failed for good (no retry left), with the
/// provider's name in front so the report says which request it was.
final class ErrorReportingObserver extends ProviderObserver {
  const ErrorReportingObserver(this.reporter);
  final ErrorReporter reporter;

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    reporter.report('provider', '${context.provider}: $error', stackTrace);
  }
}
