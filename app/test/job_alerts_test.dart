// How many alerts a job gives: the business default, one job's own choice,
// and the card that shows when alerts do not reach the phone.
import 'package:duebook/core/push/push_card.dart';
import 'package:duebook/core/push/push_service.dart';
import 'package:duebook/features/auth/auth_repository.dart';
import 'package:duebook/features/jobs/alert_settings.dart';
import 'package:duebook/features/jobs/job_alerts.dart';
import 'package:duebook/features/jobs/job_detail_screen.dart';
import 'package:duebook/features/jobs/jobs_offline.dart';
import 'package:duebook/features/jobs/jobs_repository.dart';
import 'package:duebook/features/jobs/new_job_screen.dart';
import 'package:duebook/features/spaces/spaces_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'helpers/flaky_repos.dart';
import 'helpers/pump_app.dart';

class _AsInstaller implements SpacesRepository {
  @override
  Future<List<Space>> listMine() async => const [
    Space(
      id: 'b',
      name: 'Ahmed CCTV & Solar',
      kind: SpaceKind.group,
      businessEnabled: true,
      myRole: MemberRole.member,
      memberCount: 5,
    ),
  ];

  @override
  Future<Space> createGroup(String name, {bool business = false}) =>
      throw UnimplementedError();
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _tap(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  final f = find.text(text).last;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<(ProviderContainer, String)> _openJob(
  WidgetTester tester, {
  bool installer = false,
}) async {
  _phone(tester);
  final auth = PreviewAuthRepository();
  await tester.runAsync(
    () => auth.signIn(email: 'you@example.com', password: '123456'),
  );
  final holder = ValueNotifier<Widget>(const SizedBox.shrink());
  addTearDown(holder.dispose);
  final c = await pumpScreen(
    tester,
    ValueListenableBuilder<Widget>(
      valueListenable: holder,
      builder: (_, w, _) => w,
    ),
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      if (installer) spacesRepositoryProvider.overrideWithValue(_AsInstaller()),
    ],
  );
  final jobs = c.read(jobsRepositoryProvider) as PreviewJobsRepository;
  await jobs.ready;
  final id = (await jobs.jobs('b'))
      .firstWhere((j) => j.title == '5 kW solar service')
      .id;
  holder.value = JobDetailScreen(spaceId: 'b', jobId: id);
  await tester.pumpAndSettle();
  return (c, id);
}

void main() {
  test('levels are saved and read back the same', () {
    expect(JobAlerts.fromJson(null), isNull);
    for (final a in const [
      JobAlerts.few(),
      JobAlerts.normal(),
      JobAlerts.many(),
    ]) {
      final b = JobAlerts.fromJson(a.toJson())!;
      expect(b.level, a.level);
      expect(b.forInstaller, a.forInstaller);
      expect(b.forManager, a.forManager);
    }
    final c = JobAlerts.fromJson(
      const JobAlerts.normal()
          .custom(repeats: 4, every: 10, evening: false, before: [120, 15])
          .toJson(),
    )!;
    expect(c.level, AlertLevel.custom);
    expect([c.repeats, c.every, c.evening], [4, 10, false]);
    expect(c.before, [120, 15]);
    expect(const JobAlerts.few().forInstaller, 1, reason: 'New job only');
  });

  test('another visit booked offline keeps the choice', () {
    final p = followUpParams(
      base: {
        'id': 'j1',
        'alert_settings': {'level': 'few'},
      },
      id: 'j2',
      scheduledAt: '2026-12-01T10:00:00Z',
      createdBy: 'u',
    );
    expect(pendingJobRow(p)['alert_settings'], {'level': 'few'});
  });

  testWidgets('the owner sets the business default', (tester) async {
    _phone(tester);
    final c = await pumpScreen(tester, const AlertSettingsScreen(spaceId: 'b'));
    await _tap(tester, 'Choose myself');
    await _tap(tester, '3 times');
    await _tap(tester, '2 hours');
    await _tap(tester, 'The evening before');
    await _tap(tester, 'Save');
    final a = await c.read(jobsRepositoryProvider).spaceAlerts('b');
    expect(a.level, AlertLevel.custom);
    expect(a.repeats, 3);
    expect(a.before, [120, 60]);
    expect(a.evening, isFalse);
  });

  testWidgets('the settings fit in Urdu on a small phone', (tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final c = await pumpScreen(
      tester,
      const AlertSettingsScreen(spaceId: 'b'),
      language: 'ur',
      simpleMode: true,
    );
    await c
        .read(jobsRepositoryProvider)
        .setSpaceAlerts('b', const JobAlerts.normal().custom());
    c.invalidate(spaceAlertsProvider('b'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('one job has its own choice, and can go back', (tester) async {
    final (c, id) = await _openJob(tester);
    final jobs = c.read(jobsRepositoryProvider);
    await _tap(tester, 'Alerts: Same as the business');
    await _tap(tester, 'Many');
    await _tap(tester, 'Save');
    expect((await jobs.job(id))!.alerts!.level, AlertLevel.many);
    await _tap(tester, 'Alerts: Many');
    await _tap(tester, 'Same as the business');
    await _tap(tester, 'Save');
    expect((await jobs.job(id))!.alerts, isNull);
  });

  testWidgets('an installer does not see the choice', (tester) async {
    await _openJob(tester, installer: true);
    expect(find.text('5 kW solar service'), findsWidgets);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.textContaining('Alerts: '), findsNothing);
  });

  testWidgets('a new job can have its own choice', (tester) async {
    _phone(tester);
    await pumpScreen(tester, const NewJobScreen(spaceId: 'b'));
    await _tap(tester, 'Alerts for this job');
    await _tap(tester, 'Few');
    await _tap(tester, 'Save');
    expect(find.text('Few'), findsOneWidget);
  });

  testWidgets('a failed load shows the error with a retry', (tester) async {
    final net = FakeNetwork()..offline = true;
    await pumpScreen(
      tester,
      const AlertSettingsScreen(spaceId: 'b'),
      overrides: [
        // Only the jobs side is offline; the samples load from the ledger.
        jobsRepositoryProvider.overrideWith(
          (ref) => FlakyJobs(FlakyLedger(FakeNetwork()), net),
        ),
      ],
    );
    expect(find.text('Normal'), findsNothing);
    net.offline = false;
    await _tap(tester, 'Try again');
    expect(find.text('Normal'), findsOneWidget);
  });

  testWidgets('alerts off on the phone are shown, not hidden', (tester) async {
    final c = await pumpScreen(tester, const Scaffold(body: PushCard()));
    expect(find.byType(TextButton), findsNothing);
    c.read(pushStatusProvider.notifier).state = PushStatus.off;
    await tester.pumpAndSettle();
    expect(find.text('Turn on'), findsOneWidget);
    c.read(pushStatusProvider.notifier).state = PushStatus.failed;
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    c.read(pushStatusProvider.notifier).state = PushStatus.on;
    await tester.pumpAndSettle();
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('a tapped alert opens its job after the PIN', (tester) async {
    final locked = ValueNotifier(true);
    addTearDown(locked.dispose);
    final router = GoRouter(
      initialLocation: '/spaces',
      refreshListenable: locked,
      redirect: (_, st) => locked.value
          ? '/lock'
          : (st.matchedLocation == '/lock' ? '/spaces' : null),
      routes: [
        for (final p in ['/spaces', '/lock', '/job'])
          GoRoute(path: p, builder: (_, _) => Text(p)),
      ],
    );
    addTearDown(router.dispose);
    final link = AlertLink(router);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    link.open('/job');
    await tester.pumpAndSettle();
    expect(find.text('/lock'), findsOneWidget);
    locked.value = false;
    await tester.pumpAndSettle();
    expect(find.text('/job'), findsOneWidget);
    // The lock comes up just after: still the job once it is open again.
    locked.value = true;
    await tester.pumpAndSettle();
    expect(find.text('/lock'), findsOneWidget);
    locked.value = false;
    await tester.pumpAndSettle();
    expect(find.text('/job'), findsOneWidget);
  });
}
