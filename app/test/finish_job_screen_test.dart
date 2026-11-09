import 'package:duebook/features/invoices/finish_job_screen.dart';
import 'package:duebook/features/invoices/invoices_repository.dart';
import 'package:duebook/features/jobs/jobs_models.dart';
import 'package:duebook/features/jobs/jobs_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/pump_app.dart';

void main() {
  testWidgets('quick tiles add items and the total follows', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late String jobId;
    final container = await pumpScreen(
      tester,
      Consumer(
        builder: (context, ref, _) {
          final jobs = ref.watch(jobsProvider('b')).value;
          if (jobs == null || jobs.isEmpty) return const SizedBox.shrink();
          jobId = jobs.firstWhere((j) => j.status == JobStatus.confirmed).id;
          return FinishJobScreen(spaceId: 'b', jobId: jobId);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Quick add'), findsOneWidget);
    expect(
      find.text(
        'Nothing added yet. Tap a tile above to add what you used.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.text('Rs 0'), findsOneWidget);

    await tester.tap(find.text('Dome camera 2MP').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dome camera 2MP').first);
    await tester.pumpAndSettle();
    expect(find.text('Rs 9,000'), findsWidgets);

    await tester.tap(find.text('Service charge').first);
    await tester.pumpAndSettle();
    expect(find.text('Rs 10,500'), findsOneWidget);

    // Save for later writes the lines through the repository.
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();
    final saved = await container
        .read(invoicesRepositoryProvider)
        .jobItems(jobId);
    expect(saved.length, 2);
    expect(saved.first.qty, 2);
  });
}
