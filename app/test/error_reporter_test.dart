import 'package:duebook/core/errors/error_reporter.dart';
import 'package:duebook/core/offline/offline_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Map<String, dynamic>> sent;
  late bool signedIn;

  ErrorReporter make({Future<void> Function(Map<String, dynamic>)? send}) =>
      ErrorReporter(
        send: send ?? (row) async => sent.add(row),
        signedIn: () => signedIn,
        appVersion: '0.1.0',
        platform: 'android',
      );

  setUp(() {
    sent = [];
    signedIn = true;
  });

  test('a report carries source, message, screen, version and platform', () {
    final r = make()..currentScreen = () => '/space/1/job/2';
    r.report('provider', StateError('boom'), StackTrace.current);
    expect(sent, hasLength(1));
    expect(sent.single['source'], 'provider');
    expect(sent.single['message'], contains('boom'));
    expect(sent.single['screen'], '/space/1/job/2');
    expect(sent.single['app_version'], '0.1.0');
    expect(sent.single['platform'], 'android');
    expect(sent.single['detail'], isNotEmpty);
    expect(sent.single.containsKey('user_id'), isFalse);
  });

  test('the same failure is sent once per run', () {
    final r = make();
    r.report('provider', 'same');
    r.report('provider', 'same');
    r.report('flutter', 'same');
    expect(sent, hasLength(2));
  });

  test('nothing is sent while signed out', () {
    signedIn = false;
    make().report('flutter', 'x');
    expect(sent, isEmpty);
  });

  test('no more than the cap leaves the phone in one run', () {
    final r = make();
    for (var i = 0; i < ErrorReporter.maxPerRun + 10; i++) {
      r.report('flutter', 'error $i');
    }
    expect(sent, hasLength(ErrorReporter.maxPerRun));
  });

  test('long text is cut to what the table accepts', () {
    make().report('flutter', 'x' * 5000);
    expect((sent.single['message'] as String).length, 2000);
  });

  test('a report that cannot be sent is dropped without an error', () async {
    final r = make(send: (_) async => throw StateError('offline'));
    r.report('flutter', 'x');
    await Future<void>.delayed(Duration.zero);
  });

  test('a failed data request reaches the reporter', () async {
    final r = make();
    final container = ProviderContainer(
      observers: [ErrorReportingObserver(r)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    final failing = FutureProvider<int>((ref) async => throw StateError('no'));
    container.listen(failing, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(sent, hasLength(1));
    expect(sent.single['source'], 'provider');
    expect(sent.single['message'], contains('no'));
  });

  test('a failure is reported while the app still retries it', () async {
    final r = make();
    final container = ProviderContainer(
      observers: [ErrorReportingObserver(r)],
      retry: r.retryAndReport,
    );
    addTearDown(container.dispose);
    final failing = FutureProvider<int>(
      (ref) async => throw Exception('server silent'),
    );
    container.listen(failing, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(container.read(failing).isLoading, isTrue, reason: 'still retrying');
    expect(sent, hasLength(1));
    expect(sent.single['message'], contains('server silent'));
    expect(r.retryAndReport(0, Exception('x')), isNotNull);
  });

  test('a broken screen lookup does not stop the report', () {
    final r = make()..currentScreen = () => throw StateError('router gone');
    r.report('flutter', 'x');
    expect(sent, hasLength(1));
    expect(sent.single['screen'], isNull);
  });

  test('no internet and nothing saved is not retried or reported', () {
    final r = make();
    expect(r.retryAndReport(0, const OfflineNoData('jobs:b')), isNull);
    expect(sent, isEmpty);
  });
}
