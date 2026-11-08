import 'package:duebook/features/jobs/jobs_models.dart';
import 'package:duebook/features/jobs/jobs_repository.dart';
import 'package:duebook/features/ledger/ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PreviewJobsRepository repo;
  late PreviewLedgerRepository ledger;

  setUp(() async {
    ledger = PreviewLedgerRepository();
    repo = PreviewJobsRepository(ledger);
    await Future<void>.delayed(Duration.zero); // let the sample data seed
  });

  test(
    'sample business has jobs today and a catalog with favourites',
    () async {
      final jobs = await repo.jobs('b');
      expect(jobs.where((j) => j.isToday).length, greaterThanOrEqualTo(2));
      final items = await repo.catalog('b');
      expect(items.first.isFavourite, isTrue);
      expect(
        items.any((i) => i.category == 'labour' && i.allowPriceEdit),
        isTrue,
      );
    },
  );

  test('status codes round trip to the database spelling', () {
    for (final s in JobStatus.values) {
      expect(JobStatusDb.fromDb(s.db), s);
    }
    for (final t in JobType.values) {
      expect(JobTypeDb.fromDb(t.db), t);
    }
    expect(JobStatus.onTheWay.db, 'on_the_way');
    expect(JobStatus.paid.isOpen, isFalse);
    expect(JobStatus.working.isOpen, isTrue);
  });

  test('create, confirm, and walk a job to finished', () async {
    final parties = await ledger.partiesWithBalances('b');
    final id = await repo.createJob(
      NewJob(
        spaceId: 'b',
        customerId: parties.first.party.id,
        title: 'Test job',
        type: JobType.cctvInstall,
        scheduledAt: DateTime.now().add(const Duration(days: 2)),
        assigneeIds: const ['preview', 'u6'],
      ),
    );
    var job = (await repo.job(id))!;
    expect(job.status, JobStatus.scheduled);
    expect(job.assignees.length, 2);
    expect(job.anyoneConfirmed, isFalse);
    await repo.confirm(id);
    job = (await repo.job(id))!;
    expect(job.status, JobStatus.confirmed);
    expect(
      job.assignees.firstWhere((a) => a.userId == 'preview').confirmed,
      isTrue,
    );
    await repo.setStatus(id, JobStatus.onTheWay);
    await repo.setStatus(id, JobStatus.working);
    await repo.setStatus(id, JobStatus.finished);
    job = (await repo.job(id))!;
    expect(job.status, JobStatus.finished);
    final events = await repo.events(id);
    expect(events.where((e) => e.type == 'status').length, 3);
  });

  test('rescheduling clears confirmations', () async {
    final jobs = await repo.jobs('b');
    final confirmed = jobs.firstWhere(
      (j) => j.anyoneConfirmed && j.status == JobStatus.confirmed,
    );
    await repo.reschedule(
      confirmed.id,
      DateTime.now().add(const Duration(days: 3)),
    );
    final j = (await repo.job(confirmed.id))!;
    expect(j.status, JobStatus.scheduled);
    expect(j.anyoneConfirmed, isFalse);
  });

  test('catalog items can be added and edited', () async {
    final saved = await repo.saveItem(
      const CatalogItem(
        id: '',
        spaceId: 'b',
        nameEn: 'Test cable',
        unit: 'm',
        category: 'cable',
        salePricePaisa: 5000,
      ),
      isNew: true,
    );
    expect(saved.id, isNotEmpty);
    final edited = await repo.saveItem(
      CatalogItem(
        id: saved.id,
        spaceId: 'b',
        nameEn: 'Test cable',
        unit: 'm',
        category: 'cable',
        salePricePaisa: 6000,
        isFavourite: true,
      ),
      isNew: false,
    );
    expect(edited.salePricePaisa, 6000);
    expect(
      (await repo.catalog('b')).firstWhere((i) => i.id == saved.id).isFavourite,
      isTrue,
    );
  });

  test('notifications mark read', () async {
    final before = await repo.notifications();
    final unread = before.firstWhere((n) => n.unread);
    await repo.markRead(unread.id);
    final after = await repo.notifications();
    expect(after.firstWhere((n) => n.id == unread.id).unread, isFalse);
  });
}
