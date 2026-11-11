// The installer's day: nothing may block the journey. Steps can be skipped,
// a job can be finished with no items and no bill, and "Can't finish
// today" works with nothing filled in. The owner then sets a new date.
import 'package:duebook/features/auth/auth_repository.dart';
import 'package:duebook/features/invoices/finish_job_screen.dart';
import 'package:duebook/features/invoices/invoice_models.dart';
import 'package:duebook/features/invoices/invoices_repository.dart';
import 'package:duebook/features/jobs/job_detail_screen.dart';
import 'package:duebook/features/jobs/jobs_models.dart';
import 'package:duebook/features/jobs/jobs_repository.dart';
import 'package:duebook/features/spaces/spaces_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/pump_app.dart';

/// The business book, seen by an installer (member) instead of a manager.
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

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Opens a screen after the sample jobs exist, and returns the sample job
/// assigned to "You" (5 kW solar service, scheduled).
Future<(ProviderContainer, Job)> _open(
  WidgetTester tester,
  Widget Function(Job) screen, {
  bool installer = false,
}) async {
  _phoneSize(tester);
  // Signed in as "You", the person the sample job is assigned to.
  final auth = PreviewAuthRepository();
  await tester.runAsync(
    () => auth.signIn(email: 'you@example.com', password: '123456'),
  );
  final holder = ValueNotifier<Widget>(const SizedBox.shrink());
  addTearDown(holder.dispose);
  final container = await pumpScreen(
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
  final jobs = container.read(jobsRepositoryProvider) as PreviewJobsRepository;
  await jobs.ready;
  final job = (await jobs.jobs('b'))
      .firstWhere((j) => j.title == '5 kW solar service');
  holder.value = screen(job);
  await tester.pumpAndSettle();
  return (container, job);
}

Future<JobStatus> _status(ProviderContainer c, String id) async =>
    (await c.read(jobsRepositoryProvider).job(id))!.status;

void main() {
  testWidgets('steps can be skipped: Start work and Finish from scheduled', (
    tester,
  ) async {
    final (c, job) = await _open(
      tester,
      (j) => JobDetailScreen(spaceId: 'b', jobId: j.id),
      installer: true,
    );
    expect(find.text('Start work'), findsOneWidget);
    expect(find.text('Finish job'), findsOneWidget);
    await tester.tap(find.text('Start work'));
    await tester.pumpAndSettle();
    expect(await _status(c, job.id), JobStatus.working);
  });

  testWidgets("Can't finish today needs nothing filled in", (tester) async {
    final (c, job) = await _open(
      tester,
      (j) => JobDetailScreen(spaceId: 'b', jobId: j.id),
      installer: true,
    );
    await tester.ensureVisible(find.text("Can't finish today"));
    await tester.tap(find.text("Can't finish today"));
    await tester.pumpAndSettle();
    expect(find.textContaining('Everything here is optional'), findsOneWidget);
    await tester.tap(find.text('Send to owner'));
    await tester.pumpAndSettle();
    expect(await _status(c, job.id), JobStatus.onHold);
    expect(find.text('Stopped on site'), findsOneWidget);
    expect(find.text('The owner will set a new date.'), findsOneWidget);
    expect(find.text('Set new date'), findsNothing, reason: 'installer');
    expect(find.text("Can't finish today"), findsNothing);
  });

  testWidgets('a reason and note show on the stopped job', (tester) async {
    final (c, job) = await _open(
      tester,
      (j) => JobDetailScreen(spaceId: 'b', jobId: j.id),
      installer: true,
    );
    await tester.ensureVisible(find.text("Can't finish today"));
    await tester.tap(find.text("Can't finish today"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No electricity'));
    await tester.enterText(find.byType(TextField), 'Breaker off');
    await tester.tap(find.text('Send to owner'));
    await tester.pumpAndSettle();
    final stopped = (await c.read(jobsRepositoryProvider).job(job.id))!;
    expect(stopped.holdReason, 'no_power');
    expect(find.text('No electricity'), findsOneWidget);
    expect(find.text('Breaker off'), findsOneWidget);
  });

  testWidgets('the owner sees Set new date on a stopped job', (tester) async {
    final (c, job) = await _open(
      tester,
      (j) => JobDetailScreen(spaceId: 'b', jobId: j.id),
    );
    await c.read(jobsRepositoryProvider).reportProblem(job.id);
    c.invalidate(jobProvider(('b', job.id)));
    await tester.pumpAndSettle();
    expect(find.text('Set new date'), findsOneWidget);
    expect(find.text('The owner will set a new date.'), findsNothing);
  });

  testWidgets('Done, owner will bill finishes a job with no items', (
    tester,
  ) async {
    final (c, job) = await _open(
      tester,
      (j) => FinishJobScreen(spaceId: 'b', jobId: j.id),
      installer: true,
    );
    expect(find.text('Next: make the bill'), findsOneWidget);
    await tester.tap(find.text('Done, owner will bill'));
    await tester.pumpAndSettle();
    expect(await _status(c, job.id), JobStatus.finished);
  });

  testWidgets('an Other item can be added without a price', (tester) async {
    await _open(
      tester,
      (j) => FinishJobScreen(spaceId: 'b', jobId: j.id),
      installer: true,
    );
    await tester.ensureVisible(find.text('Other charge'));
    await tester.tap(find.text('Other charge'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          )
          .first,
      'Special bracket',
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Special bracket'), findsOneWidget);
    expect(find.text('Price needed'), findsOneWidget);
  });

  testWidgets("the owner's items to take are there when finishing", (
    tester,
  ) async {
    final (c, job) = await _open(
      tester,
      (j) => FinishJobScreen(spaceId: 'b', jobId: j.id, planning: true),
    );
    expect(find.text('Items to take'), findsWidgets);
    expect(find.text('Done, owner will bill'), findsNothing);
    final items = c.read(invoicesRepositoryProvider);
    await tester.runAsync(
      () => items.setJobItems('b', job.id, [
        JobItem(
          id: '',
          jobId: job.id,
          description: 'Panel 550W',
          qty: 4,
          unitPricePaisa: 3500000,
        ),
      ]),
    );
    final saved = await tester.runAsync(() => items.jobItems(job.id));
    expect(saved!.single.description, 'Panel 550W');
  });

  testWidgets('a finished job can book another visit with its own bill', (
    tester,
  ) async {
    _phoneSize(tester);
    final holder = ValueNotifier<Widget>(const SizedBox.shrink());
    addTearDown(holder.dispose);
    final c = await pumpScreen(
      tester,
      ValueListenableBuilder<Widget>(
        valueListenable: holder,
        builder: (_, w, _) => w,
      ),
    );
    final jobs = c.read(jobsRepositoryProvider) as PreviewJobsRepository;
    await jobs.ready;
    final done = (await jobs.jobs('b'))
        .firstWhere((j) => j.status == JobStatus.finished);
    holder.value = JobDetailScreen(spaceId: 'b', jobId: done.id);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Book another visit'));
    await tester.tap(find.text('Book another visit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'What needs doing?'),
      'Add 1 more camera',
    );
    final before = (await jobs.job(done.id))!.status;
    await tester.tap(find.text('Book visit'));
    await tester.pumpAndSettle();

    final all = await jobs.jobs('b');
    final next = all.firstWhere((j) => j.title == 'Add 1 more camera');
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(next.status, JobStatus.scheduled);
    expect(next.customerId, done.customerId);
    expect(
      next.assignees.map((a) => a.userId),
      done.assignees.map((a) => a.userId),
    );
    expect(next.scheduledAt.day, tomorrow.day);
    expect(next.scheduledAt.hour, 10);
    expect(
      (await jobs.job(done.id))!.status,
      before,
      reason: 'the first job and its bill stay as they were',
    );
  });
}
