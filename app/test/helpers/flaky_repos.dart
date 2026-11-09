import 'package:duebook/core/net/timeout_client.dart';
import 'package:duebook/features/groups/groups_models.dart';
import 'package:duebook/features/groups/groups_repository.dart';
import 'package:duebook/features/invoices/invoice_models.dart';
import 'package:duebook/features/invoices/invoices_repository.dart';
import 'package:duebook/features/jobs/jobs_models.dart';
import 'package:duebook/features/jobs/jobs_repository.dart';
import 'package:duebook/features/ledger/ledger_models.dart';
import 'package:duebook/features/ledger/ledger_repository.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// A pretend network for tests. While [offline] is true every read in the
/// sample repositories fails the way a dropped connection would.
class FakeNetwork {
  bool offline = false;

  /// While true every read waits 30 seconds and then fails the way the
  /// app's request time limit does when the server never answers.
  bool hang = false;

  Future<T> read<T>(Future<T> Function() call) {
    if (offline) return Future.error(Exception('network down (test)'));
    if (hang) {
      return Future<T>.delayed(
        const Duration(seconds: 30),
        () => throw RequestTimedOut(),
      );
    }
    return call();
  }
}

class FlakyLedger extends PreviewLedgerRepository {
  FlakyLedger(this.net);
  final FakeNetwork net;

  @override
  Future<List<PartyBalance>> partiesWithBalances(String spaceId) =>
      net.read(() => super.partiesWithBalances(spaceId));
  @override
  Future<SpaceTotals> totals(String spaceId) =>
      net.read(() => super.totals(spaceId));
  @override
  Future<List<Entry>> entriesForParty(String partyId) =>
      net.read(() => super.entriesForParty(partyId));
  @override
  Future<List<Reminder>> reminders(String spaceId) =>
      net.read(() => super.reminders(spaceId));
}

class FlakyJobs extends PreviewJobsRepository {
  FlakyJobs(super.ledger, this.net);
  final FakeNetwork net;

  @override
  Future<List<Job>> jobs(String spaceId, {DateTime? from, DateTime? to}) =>
      net.read(() => super.jobs(spaceId, from: from, to: to));
  @override
  Future<Job?> job(String jobId) => net.read(() => super.job(jobId));
  @override
  Future<List<JobEvent>> events(String jobId) =>
      net.read(() => super.events(jobId));
  @override
  Future<List<CatalogItem>> catalog(
    String spaceId, {
    bool includeInactive = false,
  }) =>
      net.read(() => super.catalog(spaceId, includeInactive: includeInactive));
  @override
  Future<List<AppNotification>> notifications() =>
      net.read(super.notifications);
}

class FlakyInvoices extends PreviewInvoicesRepository {
  FlakyInvoices(super.jobs, super.ledger, this.net);
  final FakeNetwork net;

  @override
  Future<List<JobItem>> jobItems(String jobId) =>
      net.read(() => super.jobItems(jobId));
  @override
  Future<Invoice?> invoice(String invoiceId) =>
      net.read(() => super.invoice(invoiceId));
  @override
  Future<Invoice?> invoiceForJob(String jobId) =>
      net.read(() => super.invoiceForJob(jobId));
  @override
  Future<List<Invoice>> invoices(String spaceId) =>
      net.read(() => super.invoices(spaceId));
  @override
  Future<BusinessProfile?> businessProfile(String spaceId) =>
      net.read(() => super.businessProfile(spaceId));
  @override
  Future<InvoiceStats> stats(String spaceId) =>
      net.read(() => super.stats(spaceId));
  @override
  Future<List<ItemUsage>> itemsUsedThisMonth(String spaceId) =>
      net.read(() => super.itemsUsedThisMonth(spaceId));
}

class FlakyGroups extends PreviewGroupsRepository {
  FlakyGroups(super.ledger, this.net);
  final FakeNetwork net;

  @override
  Future<List<Member>> members(String spaceId) =>
      net.read(() => super.members(spaceId));
  @override
  Future<List<ActivityItem>> activity(String spaceId, {int limit = 100}) =>
      net.read(() => super.activity(spaceId, limit: limit));
}

/// Swaps every data source for one that obeys [net].
List<Override> flakyOverrides(FakeNetwork net) => [
  ledgerRepositoryProvider.overrideWith((ref) => FlakyLedger(net)),
  jobsRepositoryProvider.overrideWith(
    (ref) => FlakyJobs(ref.watch(ledgerRepositoryProvider), net),
  ),
  invoicesRepositoryProvider.overrideWith(
    (ref) => FlakyInvoices(
      ref.watch(jobsRepositoryProvider),
      ref.watch(ledgerRepositoryProvider),
      net,
    ),
  ),
  groupsRepositoryProvider.overrideWith(
    (ref) => FlakyGroups(ref.watch(ledgerRepositoryProvider), net),
  ),
];
