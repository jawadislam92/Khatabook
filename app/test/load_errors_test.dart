import 'package:duebook/features/groups/activity_screen.dart';
import 'package:duebook/features/groups/members_screen.dart';
import 'package:duebook/features/invoices/bill_screen.dart';
import 'package:duebook/features/invoices/finish_job_screen.dart';
import 'package:duebook/features/invoices/invoice_models.dart';
import 'package:duebook/features/invoices/invoice_screen.dart';
import 'package:duebook/features/invoices/invoices_repository.dart';
import 'package:duebook/features/invoices/invoices_tab.dart';
import 'package:duebook/features/jobs/business_home_screen.dart';
import 'package:duebook/features/jobs/catalog_screen.dart';
import 'package:duebook/features/jobs/job_detail_screen.dart';
import 'package:duebook/features/jobs/jobs_models.dart';
import 'package:duebook/features/jobs/jobs_repository.dart';
import 'package:duebook/features/jobs/new_job_screen.dart';
import 'package:duebook/features/jobs/notifications_screen.dart';
import 'package:duebook/features/ledger/add_entry_screen.dart';
import 'package:duebook/features/ledger/entry_detail_screen.dart';
import 'package:duebook/features/ledger/ledger_models.dart';
import 'package:duebook/features/ledger/ledger_repository.dart';
import 'package:duebook/features/ledger/party_screen.dart';
import 'package:duebook/features/ledger/space_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/flaky_repos.dart';
import 'helpers/pump_app.dart';

const _error = 'Something went wrong. Please try again.';
const _retry = 'Try again';

/// Sample ids from the same container the screen runs in.
class _Ids {
  late String job;
  late String billedJob;
  late String invoice;
  late String party;
  late String entry;
}

/// Opens [build] with the network down, checks the error and the retry
/// button are there instead of a spinner, then brings the network back,
/// taps retry until nothing is left to retry, and checks the error is gone.
Future<void> _checkScreen(
  WidgetTester tester,
  Widget Function(_Ids ids) build, {
  Finder? loaded,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final net = FakeNetwork();
  final holder = ValueNotifier<Widget>(const SizedBox.shrink());
  final container = await pumpScreen(
    tester,
    ValueListenableBuilder<Widget>(
      valueListenable: holder,
      builder: (_, w, _) => w,
    ),
    overrides: flakyOverrides(net),
  );

  // Gather ids straight from the repositories while the network is up.
  final ids = _Ids();
  final ledger = container.read(ledgerRepositoryProvider);
  final jobs = container.read(jobsRepositoryProvider) as PreviewJobsRepository;
  final invoices = container.read(invoicesRepositoryProvider);
  await jobs.ready;
  final all = await jobs.jobs('b');
  ids.job = all.firstWhere((j) => j.status == JobStatus.confirmed).id;
  final billed = all.firstWhere((j) => j.id != ids.job && j.status.isOpen);
  ids.billedJob = billed.id;
  await invoices.setJobItems('b', billed.id, [
    JobItem(
      id: '',
      jobId: billed.id,
      description: 'Service charge',
      qty: 1,
      unitPricePaisa: 150000,
    ),
  ]);
  ids.invoice = await invoices.issueInvoice(BillRequest(jobId: billed.id));
  final parties = await ledger.partiesWithBalances('b');
  final withEntries = <PartyBalance>[];
  for (final p in parties) {
    if ((await ledger.entriesForParty(p.party.id)).isNotEmpty) {
      withEntries.add(p);
    }
  }
  ids.party = withEntries.first.party.id;
  ids.entry = (await ledger.entriesForParty(ids.party)).first.id;

  net.offline = true;
  holder.value = build(ids);
  await tester.pumpAndSettle();
  expect(
    find.text(_error, skipOffstage: false),
    findsWidgets,
    reason: 'the screen shows the error while the network is down',
  );
  expect(find.text(_retry, skipOffstage: false), findsWidgets);
  expect(find.byType(CircularProgressIndicator), findsNothing);

  net.offline = false;
  for (var i = 0; i < 6; i++) {
    final retry = find.text(_retry, skipOffstage: false);
    if (retry.evaluate().isEmpty) break;
    await tester.ensureVisible(retry.first);
    await tester.pumpAndSettle();
    await tester.tap(retry.first);
    await tester.pumpAndSettle();
  }
  expect(
    find.text(_error, skipOffstage: false),
    findsNothing,
    reason: 'retry loads the data once the network is back',
  );
  if (loaded != null && loaded.evaluate().isEmpty) {
    final shown = find
        .byType(Text)
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .take(30)
        .join(' | ');
    fail('expected content missing after retry. On screen: $shown');
  }
  holder.dispose();
}

void main() {
  testWidgets('job detail', (t) async {
    await _checkScreen(
      t,
      (ids) => JobDetailScreen(spaceId: 'b', jobId: ids.job),
      loaded: find.byIcon(Icons.call_outlined),
    );
  });

  testWidgets('business home, Today tab', (t) async {
    await _checkScreen(t, (_) => const BusinessHomeScreen(spaceId: 'b'));
  });

  testWidgets('business home, Jobs tab', (t) async {
    await _checkScreen(
      t,
      (_) => const BusinessHomeScreen(spaceId: 'b', initialTab: 1),
    );
  });

  testWidgets('bills tab', (t) async {
    await _checkScreen(
      t,
      (_) => const InvoicesTab(spaceId: 'b', manager: true),
    );
  });

  testWidgets('items report', (t) async {
    await _checkScreen(t, (_) => const ItemsReportScreen(spaceId: 'b'));
  });

  testWidgets('invoice', (t) async {
    await _checkScreen(
      t,
      (ids) => InvoiceScreen(spaceId: 'b', invoiceId: ids.invoice),
      loaded: find.text('Unpaid'),
    );
  });

  testWidgets('bill', (t) async {
    await _checkScreen(
      t,
      (ids) => BillScreen(spaceId: 'b', jobId: ids.billedJob),
      loaded: find.textContaining(' × 1'),
    );
  });

  testWidgets('finish job', (t) async {
    await _checkScreen(
      t,
      (ids) => FinishJobScreen(spaceId: 'b', jobId: ids.job),
      loaded: find.text('Quick add'),
    );
  });

  testWidgets('space home', (t) async {
    await _checkScreen(t, (_) => const SpaceHomeScreen(spaceId: 'b'));
  });

  testWidgets('person ledger', (t) async {
    await _checkScreen(
      t,
      (ids) => PartyScreen(spaceId: 'b', partyId: ids.party),
    );
  });

  testWidgets('entry detail', (t) async {
    await _checkScreen(
      t,
      (ids) => EntryDetailScreen(
        spaceId: 'b',
        partyId: ids.party,
        entryId: ids.entry,
      ),
    );
  });

  testWidgets('new job', (t) async {
    await _checkScreen(t, (_) => const NewJobScreen(spaceId: 'b'));
  });

  testWidgets('add entry, choosing the person', (t) async {
    await _checkScreen(
      t,
      (_) => const AddEntryScreen(spaceId: 'b', direction: EntryDirection.gave),
    );
  });

  testWidgets('catalog', (t) async {
    await _checkScreen(t, (_) => const CatalogScreen(spaceId: 'b'));
  });

  testWidgets('members', (t) async {
    await _checkScreen(t, (_) => const MembersScreen(spaceId: 'b'));
  });

  testWidgets('activity', (t) async {
    await _checkScreen(t, (_) => const ActivityScreen(spaceId: 'b'));
  });

  testWidgets('notifications', (t) async {
    await _checkScreen(t, (_) => const NotificationsScreen());
  });
}
