import 'package:duebook/features/invoices/invoice_models.dart';
import 'package:duebook/features/invoices/invoices_repository.dart';
import 'package:duebook/features/jobs/jobs_models.dart';
import 'package:duebook/features/jobs/jobs_repository.dart';
import 'package:duebook/features/ledger/ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PreviewLedgerRepository ledger;
  late PreviewJobsRepository jobs;
  late PreviewInvoicesRepository repo;

  setUp(() async {
    ledger = PreviewLedgerRepository();
    jobs = PreviewJobsRepository(ledger);
    repo = PreviewInvoicesRepository(jobs, ledger);
    await repo.invoices('b'); // waits for the sample data
  });

  test('formatQty drops trailing zeros', () {
    expect(formatQty(2), '2');
    expect(formatQty(2.5), '2.5');
    expect(formatQty(12.375), '12.375');
    expect(formatQty(3.100), '3.1');
  });

  test('status and method codes round trip', () {
    for (final s in InvoiceStatus.values) {
      expect(InvoiceStatusDb.fromDb(s.db), s);
    }
    expect(InvoiceStatus.voided.db, 'void');
    for (final m in PaymentMethod.values) {
      expect(PaymentMethodDb.fromDb(m.db), m);
    }
  });

  test('sample business has one partly paid bill and a profile', () async {
    final list = await repo.invoices('b');
    expect(list.length, 1);
    final inv = list.single;
    expect(inv.isOpen, isTrue);
    expect(inv.receivedPaisa, 10000 * 100);
    expect(inv.balancePaisa, inv.totalPaisa - inv.receivedPaisa);
    expect(inv.number, startsWith('INV-'));
    final profile = await repo.businessProfile('b');
    expect(profile?.isComplete, isTrue);
    final stats = await repo.stats('b');
    expect(stats.unpaidCount, 1);
    expect(stats.unpaidPaisa, inv.balancePaisa);
  });

  test('issuing a bill moves the khata and the job', () async {
    final working = (await jobs.jobs('b'))
        .firstWhere((j) => j.status == JobStatus.confirmed);
    await jobs.setStatus(working.id, JobStatus.working);
    final catalog = await jobs.catalog('b');
    final cam = catalog.firstWhere((i) => i.nameEn.startsWith('Dome'));
    final before = (await ledger.partiesWithBalances('b'))
        .firstWhere((p) => p.party.id == working.customerId)
        .balancePaisa;

    await repo.setJobItems('b', working.id, [
      JobItem(
        id: '',
        jobId: working.id,
        itemId: cam.id,
        description: cam.nameEn,
        qty: 2,
        unit: cam.unit,
        unitPricePaisa: cam.salePricePaisa,
      ),
      JobItem(
        id: '',
        jobId: working.id,
        description: 'Transport',
        qty: 1,
        unitPricePaisa: 500 * 100,
      ),
    ]);
    final saved = await repo.jobItems(working.id);
    expect(saved.length, 2);
    expect(saved.first.id, isNotEmpty);

    final subtotal = 2 * cam.salePricePaisa + 500 * 100;
    final id = await repo.issueInvoice(
      BillRequest(
        jobId: working.id,
        discountPaisa: 500 * 100,
        receivedPaisa: 1000 * 100,
        method: PaymentMethod.easypaisa,
      ),
    );
    final inv = (await repo.invoice(id))!;
    expect(inv.subtotalPaisa, subtotal);
    expect(inv.totalPaisa, subtotal - 500 * 100);
    expect(inv.balancePaisa, subtotal - 500 * 100 - 1000 * 100);
    expect(inv.lines.length, 2);
    expect(inv.payments.single.method, PaymentMethod.easypaisa);
    expect((await jobs.job(working.id))!.status, JobStatus.invoiced);
    expect(await repo.invoiceForJob(working.id), isNotNull);

    final after = (await ledger.partiesWithBalances('b'))
        .firstWhere((p) => p.party.id == working.customerId)
        .balancePaisa;
    expect(after - before, inv.balancePaisa);

    // Paying the rest closes the bill and the job.
    await repo.recordPayment(id, inv.balancePaisa, PaymentMethod.cash);
    final paid = (await repo.invoice(id))!;
    expect(paid.isPaid, isTrue);
    expect(paid.balancePaisa, 0);
    expect((await jobs.job(working.id))!.status, JobStatus.paid);
    final settled = (await ledger.partiesWithBalances('b'))
        .firstWhere((p) => p.party.id == working.customerId)
        .balancePaisa;
    expect(settled, before);

    // Overpaying is refused.
    expect(
      () => repo.recordPayment(id, 1, PaymentMethod.cash),
      throwsStateError,
    );
  });

  test('voiding a bill reverses everything', () async {
    final inv = (await repo.invoices('b')).single;
    final before = (await ledger.partiesWithBalances('b'))
        .firstWhere((p) => p.party.id == inv.customerId)
        .balancePaisa;
    await repo.voidInvoice(inv.id);
    final voided = (await repo.invoice(inv.id))!;
    expect(voided.isVoid, isTrue);
    expect(voided.payments.every((p) => p.isVoided), isTrue);
    expect(await repo.invoiceForJob(inv.jobId!), isNull);
    expect((await jobs.job(inv.jobId!))!.status, JobStatus.finished);
    final after = (await ledger.partiesWithBalances('b'))
        .firstWhere((p) => p.party.id == inv.customerId)
        .balancePaisa;
    expect(after, before - inv.balancePaisa);
    expect((await repo.stats('b')).unpaidCount, 0);
    expect(() => repo.voidInvoice(inv.id), throwsStateError);
  });

  test('bill maths matches the database rules', () {
    const items = [
      JobItem(
        id: '',
        jobId: 'j',
        description: 'a',
        qty: 2.5,
        unitPricePaisa: 4500,
      ),
      JobItem(
        id: '',
        jobId: 'j',
        description: 'b',
        qty: 1,
        unitPricePaisa: 100,
      ),
    ];
    expect(BillMath.subtotal(items), 11350);
    const profile = BusinessProfile(
      spaceId: 'b',
      nameEn: 'x',
      taxEnabled: true,
      taxRateBp: 1700,
    );
    expect(BillMath.tax(10000, 0, profile), 1700);
    expect(BillMath.tax(10000, 2000, profile), 1360);
    expect(BillMath.tax(10000, 0, null), 0);
    expect(
      BillMath.tax(10000, 0, const BusinessProfile(spaceId: 'b', nameEn: 'x')),
      0,
    );
  });
}
