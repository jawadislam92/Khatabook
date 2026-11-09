import 'package:duebook/features/jobs/jobs_models.dart';
import 'package:duebook/features/jobs/jobs_repository.dart';
import 'package:duebook/features/jobs/job_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/flaky_repos.dart';
import 'helpers/pump_app.dart';

/// When the server never answers, each request gives up after 30 seconds.
/// The screen must then show the error with a retry button, even though the
/// app keeps trying again in the background.
void main() {
  testWidgets('job detail shows the error 30 seconds after no answer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final net = FakeNetwork();
    final holder = ValueNotifier<Widget>(const SizedBox.shrink());
    addTearDown(holder.dispose);
    final container = await pumpScreen(
      tester,
      ValueListenableBuilder<Widget>(
        valueListenable: holder,
        builder: (_, w, _) => w,
      ),
      overrides: flakyOverrides(net),
      appRetry: true,
    );
    final jobs =
        container.read(jobsRepositoryProvider) as PreviewJobsRepository;
    await jobs.ready;
    final id = (await jobs.jobs('b'))
        .firstWhere((j) => j.status == JobStatus.confirmed)
        .id;

    net.hang = true;
    holder.value = JobDetailScreen(spaceId: 'b', jobId: id);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 29));
    expect(find.text('Try again'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.text('Try again'),
      findsWidgets,
      reason: 'the error shows once the first request gives up',
    );

    // It must stay on the error while background tries keep hanging.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Try again'), findsWidgets, reason: 'after ${i + 1}0s');
    }

    // Network back: Try again loads the job.
    net.hang = false;
    await tester.tap(find.text('Try again').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Try again'), findsNothing);
    expect(find.byIcon(Icons.call_outlined), findsOneWidget);

    // Leave no timers behind.
    holder.value = const SizedBox.shrink();
    await tester.pump(const Duration(minutes: 5));
  });
}
