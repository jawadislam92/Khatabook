import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../jobs/jobs_models.dart';
import '../jobs/jobs_repository.dart';
import '../ledger/ledger_models.dart';
import '../ledger/ledger_repository.dart';
import 'invoice_models.dart';

abstract class InvoicesRepository {
  Future<List<JobItem>> jobItems(String jobId);

  /// Replaces the job's item list with [items]. Ids on new lines are ignored.
  Future<void> setJobItems(String spaceId, String jobId, List<JobItem> items);
  Future<String> issueInvoice(BillRequest request);
  Future<Invoice?> invoice(String invoiceId);
  Future<Invoice?> invoiceForJob(String jobId);
  Future<List<Invoice>> invoices(String spaceId);
  Future<String> recordPayment(
    String invoiceId,
    int amountPaisa,
    PaymentMethod method, {
    DateTime? paidAt,
    String? note,
  });
  Future<void> voidInvoice(String invoiceId, {String? note});
  Future<BusinessProfile?> businessProfile(String spaceId);
  Future<void> saveBusinessProfile(BusinessProfile profile);
  Future<InvoiceStats> stats(String spaceId);
  Future<List<ItemUsage>> itemsUsedThisMonth(String spaceId);
  Stream<void> changes(String spaceId);
}

String _ts(DateTime d) => d.toUtc().toIso8601String();
double _num(Object? v) => v == null ? 0 : num.parse(v.toString()).toDouble();
int _int(Object? v) => v == null ? 0 : (v as num).toInt();

class SupabaseInvoicesRepository implements InvoicesRepository {
  SupabaseInvoicesRepository(this._c);
  final sb.SupabaseClient _c;
  final _local = StreamController<String>.broadcast();

  static const _select =
      '*, invoice_lines(*), payments(*), parties:customer_id(name, phone_display, address), jobs:job_id(title)';

  Invoice _invoice(Map<String, dynamic> r) {
    final lines = [
      for (final l in (r['invoice_lines'] as List? ?? const []))
        InvoiceLine(
          id: l['id'] as String,
          itemId: l['item_id'] as String?,
          description: l['description'] as String,
          qty: _num(l['qty']),
          unit: l['unit'] as String?,
          unitPricePaisa: _int(l['unit_price_paisa']),
          amountPaisa: _int(l['amount_paisa']),
          sortOrder: _int(l['sort_order']),
        ),
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final payments = [
      for (final p in (r['payments'] as List? ?? const []))
        Payment(
          id: p['id'] as String,
          invoiceId: p['invoice_id'] as String,
          method: PaymentMethodDb.fromDb(p['method'] as String),
          amountPaisa: _int(p['amount_paisa']),
          paidAt: DateTime.parse(p['paid_at'] as String).toLocal(),
          note: p['note'] as String?,
          voidedAt: p['voided_at'] == null
              ? null
              : DateTime.parse(p['voided_at'] as String),
        ),
    ]..sort((a, b) => a.paidAt.compareTo(b.paidAt));
    final party = r['parties'] as Map?;
    return Invoice(
      id: r['id'] as String,
      spaceId: r['space_id'] as String,
      jobId: r['job_id'] as String?,
      jobTitle: (r['jobs'] as Map?)?['title'] as String?,
      customerId: r['customer_id'] as String,
      customerName: party?['name'] as String? ?? '',
      customerPhone: party?['phone_display'] as String?,
      customerAddress: party?['address'] as String?,
      number: r['number'] as String,
      issuedAt: DateTime.parse(r['issued_at'] as String).toLocal(),
      subtotalPaisa: _int(r['subtotal_paisa']),
      discountPaisa: _int(r['discount_paisa']),
      taxRateBp: _int(r['tax_rate_bp']),
      taxPaisa: _int(r['tax_paisa']),
      totalPaisa: _int(r['total_paisa']),
      receivedPaisa: _int(r['received_paisa']),
      balancePaisa: _int(r['balance_paisa']),
      status: InvoiceStatusDb.fromDb(r['status'] as String),
      notes: r['notes'] as String?,
      termsText: r['terms_text'] as String?,
      lines: lines,
      payments: payments,
      voidedAt: r['voided_at'] == null
          ? null
          : DateTime.parse(r['voided_at'] as String),
    );
  }

  @override
  Future<List<JobItem>> jobItems(String jobId) async {
    final rows = await _c
        .from('job_items')
        .select('*, items:item_id(unit)')
        .eq('job_id', jobId)
        .order('created_at');
    return [
      for (final r in rows)
        JobItem(
          id: r['id'] as String,
          jobId: jobId,
          itemId: r['item_id'] as String?,
          description: r['description'] as String,
          qty: _num(r['qty']),
          unit: (r['items'] as Map?)?['unit'] as String?,
          unitPricePaisa: _int(r['unit_price_paisa']),
          note: r['note'] as String?,
        ),
    ];
  }

  @override
  Future<void> setJobItems(
    String spaceId,
    String jobId,
    List<JobItem> items,
  ) async {
    final uid = _c.auth.currentUser!.id;
    final keep = <String>[];
    if (items.isNotEmpty) {
      final inserted = await _c
          .from('job_items')
          .insert([
            for (final i in items)
              {
                'job_id': jobId,
                'space_id': spaceId,
                'item_id': i.itemId,
                'description': i.description.trim(),
                'qty': i.qty,
                'unit_price_paisa': i.unitPricePaisa,
                'note': i.note,
                'created_by': uid,
              },
          ])
          .select('id');
      keep.addAll([for (final r in inserted) r['id'] as String]);
    }
    var del = _c.from('job_items').delete().eq('job_id', jobId);
    if (keep.isNotEmpty) del = del.not('id', 'in', '(${keep.join(',')})');
    await del;
    _local.add(spaceId);
  }

  @override
  Future<String> issueInvoice(BillRequest r) async {
    final id = await _c.rpc<String>(
      'issue_invoice',
      params: {
        'p_job': r.jobId,
        'p_discount_paisa': r.discountPaisa,
        'p_received_paisa': r.receivedPaisa,
        'p_method': r.method.db,
        'p_notes': r.notes,
      },
    );
    _local.add('*');
    return id;
  }

  @override
  Future<Invoice?> invoice(String invoiceId) async {
    final r = await _c
        .from('invoices')
        .select(_select)
        .eq('id', invoiceId)
        .maybeSingle();
    return r == null ? null : _invoice(r);
  }

  @override
  Future<Invoice?> invoiceForJob(String jobId) async {
    final r = await _c
        .from('invoices')
        .select(_select)
        .eq('job_id', jobId)
        .neq('status', 'void')
        .maybeSingle();
    return r == null ? null : _invoice(r);
  }

  @override
  Future<List<Invoice>> invoices(String spaceId) async {
    final rows = await _c
        .from('invoices')
        .select(_select)
        .eq('space_id', spaceId)
        .order('issued_at', ascending: false)
        .limit(300);
    return [for (final r in rows) _invoice(r)];
  }

  @override
  Future<String> recordPayment(
    String invoiceId,
    int amountPaisa,
    PaymentMethod method, {
    DateTime? paidAt,
    String? note,
  }) async {
    final id = await _c.rpc<String>(
      'record_payment',
      params: {
        'p_invoice': invoiceId,
        'p_amount_paisa': amountPaisa,
        'p_method': method.db,
        'p_paid_at': _ts(paidAt ?? DateTime.now()),
        'p_note': note,
      },
    );
    _local.add('*');
    return id;
  }

  @override
  Future<void> voidInvoice(String invoiceId, {String? note}) async {
    await _c.rpc<void>(
      'void_invoice',
      params: {'p_invoice': invoiceId, 'p_note': note},
    );
    _local.add('*');
  }

  @override
  Future<BusinessProfile?> businessProfile(String spaceId) async {
    final r = await _c
        .from('business_profiles')
        .select()
        .eq('space_id', spaceId)
        .maybeSingle();
    if (r == null) return null;
    return BusinessProfile(
      spaceId: spaceId,
      nameEn: r['name_en'] as String? ?? '',
      nameUr: r['name_ur'] as String?,
      tagline: r['tagline'] as String?,
      address: r['address'] as String?,
      phone: r['phone'] as String?,
      email: r['email'] as String?,
      bankName: r['bank_name'] as String?,
      accountTitle: r['account_title'] as String?,
      accountNumber: r['account_number'] as String?,
      easypaisa: r['easypaisa'] as String?,
      jazzcash: r['jazzcash'] as String?,
      termsText: r['terms_text'] as String?,
      taxEnabled: r['tax_enabled'] as bool? ?? false,
      taxRateBp: _int(r['tax_rate_bp']),
      invoicePrefix: r['invoice_prefix'] as String? ?? 'INV',
    );
  }

  String? _clean(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  @override
  Future<void> saveBusinessProfile(BusinessProfile p) async {
    await _c.from('business_profiles').upsert({
      'space_id': p.spaceId,
      'name_en': p.nameEn.trim(),
      'name_ur': _clean(p.nameUr),
      'tagline': _clean(p.tagline),
      'address': _clean(p.address),
      'phone': _clean(p.phone),
      'email': _clean(p.email),
      'bank_name': _clean(p.bankName),
      'account_title': _clean(p.accountTitle),
      'account_number': _clean(p.accountNumber),
      'easypaisa': _clean(p.easypaisa),
      'jazzcash': _clean(p.jazzcash),
      'terms_text': _clean(p.termsText),
      'tax_enabled': p.taxEnabled,
      'tax_rate_bp': p.taxRateBp,
      'invoice_prefix': p.invoicePrefix.trim().isEmpty
          ? 'INV'
          : p.invoicePrefix.trim().toUpperCase(),
    }, onConflict: 'space_id');
    _local.add(p.spaceId);
  }

  @override
  Future<InvoiceStats> stats(String spaceId) async {
    final r = await _c
        .from('invoice_stats')
        .select()
        .eq('space_id', spaceId)
        .maybeSingle();
    if (r == null) return InvoiceStats.zero;
    return InvoiceStats(
      unpaidCount: _int(r['unpaid_count']),
      unpaidPaisa: _int(r['unpaid_paisa']),
      monthInvoicedPaisa: _int(r['month_invoiced_paisa']),
      monthReceivedPaisa: _int(r['month_received_paisa']),
      monthJobsDone: _int(r['month_jobs_done']),
    );
  }

  @override
  Future<List<ItemUsage>> itemsUsedThisMonth(String spaceId) async {
    final rows = await _c
        .from('items_used_month')
        .select()
        .eq('space_id', spaceId)
        .order('amount_paisa', ascending: false);
    return [
      for (final r in rows)
        ItemUsage(
          itemId: r['item_id'] as String?,
          description: r['description'] as String,
          unit: r['unit'] as String?,
          qty: _num(r['qty']),
          amountPaisa: _int(r['amount_paisa']),
        ),
    ];
  }

  @override
  Stream<void> changes(String spaceId) {
    final controller = StreamController<void>.broadcast();
    final sub = _local.stream
        .where((s) => s == '*' || s == spaceId)
        .listen((_) => controller.add(null));
    final channel = _c
        .channel('invoices-$spaceId')
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.all,
          schema: 'public',
          table: 'invoices',
          filter: sb.PostgresChangeFilter(
            type: sb.PostgresChangeFilterType.eq,
            column: 'space_id',
            value: spaceId,
          ),
          callback: (_) => controller.add(null),
        )
        .subscribe();
    controller.onCancel = () {
      sub.cancel();
      _c.removeChannel(channel);
    };
    return controller.stream;
  }
}

/// Preview mode: bills live in memory and still move the sample khata.
class PreviewInvoicesRepository implements InvoicesRepository {
  PreviewInvoicesRepository(this._jobs, this._ledger) {
    _ready = _seed();
  }
  final JobsRepository _jobs;
  final LedgerRepository _ledger;
  final _uuid = const Uuid();
  final _items = <String, List<JobItem>>{};
  final _invoices = <Invoice>[];
  final _profiles = <String, BusinessProfile>{};
  final _counters = <String, int>{};
  final _changes = StreamController<String>.broadcast();
  late final Future<void> _ready;

  Future<void> _seed() async {
    _profiles['b'] = const BusinessProfile(
      spaceId: 'b',
      nameEn: 'Ahmed CCTV & Solar',
      nameUr: 'احمد سی سی ٹی وی اینڈ سولر',
      tagline: 'Cameras, solar, and peace of mind',
      address: 'Shop 4, Commercial Market, Rawalpindi',
      phone: '0300 1234567',
      easypaisa: '0300 1234567',
      bankName: 'Meezan Bank',
      accountTitle: 'Ahmed Khan',
      accountNumber: 'PK00MEZN0000000000000000',
      termsText: 'One year warranty on installation work. Goods once sold are not returned.',
    );
    if (_jobs is PreviewJobsRepository) await _jobs.ready;
    final finished = (await _jobs.jobs('b'))
        .where((j) => j.status == JobStatus.finished)
        .firstOrNull;
    if (finished == null) return;
    final catalog = await _jobs.catalog('b');
    CatalogItem pick(String name) =>
        catalog.firstWhere((i) => i.nameEn == name);
    final dvr = pick('8 channel DVR');
    final labour = pick('Installation labour');
    _items[finished.id] = [
      JobItem(
        id: _uuid.v4(),
        jobId: finished.id,
        itemId: dvr.id,
        description: dvr.nameEn,
        qty: 1,
        unit: dvr.unit,
        unitPricePaisa: dvr.salePricePaisa,
      ),
      JobItem(
        id: _uuid.v4(),
        jobId: finished.id,
        itemId: labour.id,
        description: labour.nameEn,
        qty: 2,
        unit: labour.unit,
        unitPricePaisa: labour.salePricePaisa,
      ),
    ];
    await issueInvoice(
      BillRequest(
        jobId: finished.id,
        receivedPaisa: 10000 * 100,
        method: PaymentMethod.cash,
      ),
    );
  }

  @override
  Future<List<JobItem>> jobItems(String jobId) async {
    await _ready;
    return List.of(_items[jobId] ?? const []);
  }

  @override
  Future<void> setJobItems(
    String spaceId,
    String jobId,
    List<JobItem> items,
  ) async {
    _items[jobId] = [
      for (final i in items)
        JobItem(
          id: i.id.isEmpty ? _uuid.v4() : i.id,
          jobId: jobId,
          itemId: i.itemId,
          description: i.description.trim(),
          qty: i.qty,
          unit: i.unit,
          unitPricePaisa: i.unitPricePaisa,
          note: i.note,
        ),
    ];
    _changes.add(spaceId);
  }

  String _nextNumber(String spaceId) {
    final year = DateTime.now().year;
    final key = '$spaceId:$year';
    final n = (_counters[key] ?? 0) + 1;
    _counters[key] = n;
    final prefix = _profiles[spaceId]?.invoicePrefix ?? 'INV';
    return '$prefix-$year-${n.toString().padLeft(4, '0')}';
  }

  @override
  Future<String> issueInvoice(BillRequest r) async {
    final job = (await _jobs.job(r.jobId))!;
    final items = _items[r.jobId] ?? const [];
    if (items.isEmpty) {
      throw StateError('Add at least one item or charge first');
    }
    final profile = _profiles[job.spaceId];
    final subtotal = BillMath.subtotal(items);
    if (r.discountPaisa < 0 || r.discountPaisa > subtotal) {
      throw StateError('Discount cannot exceed the subtotal');
    }
    final tax = BillMath.tax(subtotal, r.discountPaisa, profile);
    final total = subtotal - r.discountPaisa + tax;
    if (r.receivedPaisa < 0 || r.receivedPaisa > total) {
      throw StateError('Received cannot exceed the total');
    }
    final number = _nextNumber(job.spaceId);
    final id = _uuid.v4();
    final today = DateTime.now();
    await _ledger.addEntry(
      NewEntry(
        spaceId: job.spaceId,
        partyId: job.customerId,
        direction: EntryDirection.gave,
        amountPaisa: total,
        entryDate: today,
        note: 'Invoice $number: ${job.title}',
      ),
    );
    final payments = <Payment>[];
    if (r.receivedPaisa > 0) {
      payments.add(
        Payment(
          id: _uuid.v4(),
          invoiceId: id,
          method: r.method,
          amountPaisa: r.receivedPaisa,
          paidAt: today,
        ),
      );
      await _ledger.addEntry(
        NewEntry(
          spaceId: job.spaceId,
          partyId: job.customerId,
          direction: EntryDirection.got,
          amountPaisa: r.receivedPaisa,
          entryDate: today,
          note: 'Payment (${r.method.db}) for $number',
        ),
      );
    }
    final balance = total - r.receivedPaisa;
    var order = 0;
    _invoices.insert(
      0,
      Invoice(
        id: id,
        spaceId: job.spaceId,
        jobId: job.id,
        jobTitle: job.title,
        customerId: job.customerId,
        customerName: job.customerName,
        customerPhone: job.customerPhone,
        customerAddress: job.address,
        number: number,
        issuedAt: today,
        subtotalPaisa: subtotal,
        discountPaisa: r.discountPaisa,
        taxRateBp: profile?.taxEnabled ?? false ? profile!.taxRateBp : 0,
        taxPaisa: tax,
        totalPaisa: total,
        receivedPaisa: r.receivedPaisa,
        balancePaisa: balance,
        status: balance == 0 ? InvoiceStatus.paid : InvoiceStatus.issued,
        notes: r.notes,
        termsText: profile?.termsText,
        lines: [
          for (final i in items)
            InvoiceLine(
              id: _uuid.v4(),
              itemId: i.itemId,
              description: i.description,
              qty: i.qty,
              unit: i.unit,
              unitPricePaisa: i.unitPricePaisa,
              amountPaisa: i.amountPaisa,
              sortOrder: order++,
            ),
        ],
        payments: payments,
      ),
    );
    await _jobs.setStatus(
      job.id,
      balance == 0 ? JobStatus.paid : JobStatus.invoiced,
      note: number,
    );
    _changes.add(job.spaceId);
    return id;
  }

  @override
  Future<Invoice?> invoice(String invoiceId) async {
    await _ready;
    return _invoices.where((i) => i.id == invoiceId).firstOrNull;
  }

  @override
  Future<Invoice?> invoiceForJob(String jobId) async {
    await _ready;
    return _invoices.where((i) => i.jobId == jobId && !i.isVoid).firstOrNull;
  }

  @override
  Future<List<Invoice>> invoices(String spaceId) async {
    await _ready;
    return _invoices.where((i) => i.spaceId == spaceId).toList();
  }

  void _replace(Invoice inv) {
    _invoices[_invoices.indexWhere((i) => i.id == inv.id)] = inv;
    _changes.add(inv.spaceId);
  }

  @override
  Future<String> recordPayment(
    String invoiceId,
    int amountPaisa,
    PaymentMethod method, {
    DateTime? paidAt,
    String? note,
  }) async {
    final inv = (await invoice(invoiceId))!;
    if (inv.isVoid) throw StateError('This invoice is void');
    if (amountPaisa <= 0 || amountPaisa > inv.balancePaisa) {
      throw StateError('Amount must be between 1 and the balance due');
    }
    final pay = Payment(
      id: _uuid.v4(),
      invoiceId: invoiceId,
      method: method,
      amountPaisa: amountPaisa,
      paidAt: paidAt ?? DateTime.now(),
      note: note,
    );
    await _ledger.addEntry(
      NewEntry(
        spaceId: inv.spaceId,
        partyId: inv.customerId,
        direction: EntryDirection.got,
        amountPaisa: amountPaisa,
        entryDate: pay.paidAt,
        note: 'Payment (${method.db}) for ${inv.number}',
      ),
    );
    final balance = inv.balancePaisa - amountPaisa;
    _replace(
      inv.copyWith(
        receivedPaisa: inv.receivedPaisa + amountPaisa,
        balancePaisa: balance,
        status: balance == 0 ? InvoiceStatus.paid : inv.status,
        payments: [...inv.payments, pay],
      ),
    );
    if (balance == 0 && inv.jobId != null) {
      await _jobs.setStatus(inv.jobId!, JobStatus.paid, note: inv.number);
    }
    return pay.id;
  }

  @override
  Future<void> voidInvoice(String invoiceId, {String? note}) async {
    final inv = (await invoice(invoiceId))!;
    if (inv.isVoid) throw StateError('Already void');
    final entries = await _ledger.entriesForParty(inv.customerId);
    for (final e in entries.where(
      (e) =>
          !e.isVoided &&
          !e.isReversal &&
          (e.note?.contains(inv.number) ?? false),
    )) {
      await _ledger.voidEntry(
        e.id,
        note: note ?? 'Invoice ${inv.number} voided',
      );
    }
    final now = DateTime.now();
    _replace(
      inv.copyWith(
        status: InvoiceStatus.voided,
        balancePaisa: 0,
        voidedAt: now,
        payments: [
          for (final p in inv.payments)
            Payment(
              id: p.id,
              invoiceId: p.invoiceId,
              method: p.method,
              amountPaisa: p.amountPaisa,
              paidAt: p.paidAt,
              note: p.note,
              voidedAt: now,
            ),
        ],
      ),
    );
    if (inv.jobId != null) {
      await _jobs.setStatus(
        inv.jobId!,
        JobStatus.finished,
        note: 'Invoice ${inv.number} voided',
      );
    }
  }

  @override
  Future<BusinessProfile?> businessProfile(String spaceId) async {
    await _ready;
    return _profiles[spaceId];
  }

  @override
  Future<void> saveBusinessProfile(BusinessProfile profile) async {
    _profiles[profile.spaceId] = profile;
    _changes.add(profile.spaceId);
  }

  @override
  Future<InvoiceStats> stats(String spaceId) async {
    await _ready;
    final now = DateTime.now();
    bool thisMonth(DateTime d) => d.year == now.year && d.month == now.month;
    final mine = _invoices.where((i) => i.spaceId == spaceId);
    final unpaid = mine.where((i) => i.isOpen);
    final jobs = await _jobs.jobs(spaceId);
    return InvoiceStats(
      unpaidCount: unpaid.length,
      unpaidPaisa: unpaid.fold(0, (s, i) => s + i.balancePaisa),
      monthInvoicedPaisa: mine
          .where((i) => !i.isVoid && thisMonth(i.issuedAt))
          .fold(0, (s, i) => s + i.totalPaisa),
      monthReceivedPaisa: mine
          .expand((i) => i.payments)
          .where((p) => !p.isVoided && thisMonth(p.paidAt))
          .fold(0, (s, p) => s + p.amountPaisa),
      monthJobsDone: jobs
          .where(
            (j) =>
                thisMonth(j.scheduledAt) &&
                (j.status == JobStatus.finished ||
                    j.status == JobStatus.invoiced ||
                    j.status == JobStatus.paid),
          )
          .length,
    );
  }

  @override
  Future<List<ItemUsage>> itemsUsedThisMonth(String spaceId) async {
    await _ready;
    final now = DateTime.now();
    final byKey = <String, ItemUsage>{};
    for (final inv in _invoices.where(
      (i) =>
          i.spaceId == spaceId &&
          !i.isVoid &&
          i.issuedAt.year == now.year &&
          i.issuedAt.month == now.month,
    )) {
      for (final l in inv.lines) {
        final key = l.itemId ?? 'text:${l.description}';
        final prev = byKey[key];
        byKey[key] = ItemUsage(
          itemId: l.itemId,
          description: l.description,
          unit: l.unit,
          qty: (prev?.qty ?? 0) + l.qty,
          amountPaisa: (prev?.amountPaisa ?? 0) + l.amountPaisa,
        );
      }
    }
    return byKey.values.toList()
      ..sort((a, b) => b.amountPaisa.compareTo(a.amountPaisa));
  }

  @override
  Stream<void> changes(String spaceId) =>
      _changes.stream.where((s) => s == '*' || s == spaceId);
}

final invoicesRepositoryProvider = Provider<InvoicesRepository>((ref) {
  if (AppConfig.isConfigured) {
    return SupabaseInvoicesRepository(sb.Supabase.instance.client);
  }
  return PreviewInvoicesRepository(
    ref.watch(jobsRepositoryProvider),
    ref.watch(ledgerRepositoryProvider),
  );
});

final invoicesVersionProvider = StreamProvider.family<int, String>((
  ref,
  spaceId,
) {
  var n = 0;
  final c = StreamController<int>();
  c.add(0);
  final sub = ref
      .watch(invoicesRepositoryProvider)
      .changes(spaceId)
      .listen((_) => c.add(++n));
  ref.onDispose(() {
    sub.cancel();
    c.close();
  });
  return c.stream;
});

final jobItemsProvider = FutureProvider.family<List<JobItem>, (String, String)>(
  (ref, key) {
    ref.watch(invoicesVersionProvider(key.$1));
    return ref.watch(invoicesRepositoryProvider).jobItems(key.$2);
  },
);

final invoiceProvider = FutureProvider.family<Invoice?, (String, String)>((
  ref,
  key,
) {
  ref.watch(invoicesVersionProvider(key.$1));
  return ref.watch(invoicesRepositoryProvider).invoice(key.$2);
});

final invoiceForJobProvider = FutureProvider.family<Invoice?, (String, String)>(
  (ref, key) {
    ref.watch(invoicesVersionProvider(key.$1));
    return ref.watch(invoicesRepositoryProvider).invoiceForJob(key.$2);
  },
);

final invoicesProvider = FutureProvider.family<List<Invoice>, String>((
  ref,
  spaceId,
) {
  ref.watch(invoicesVersionProvider(spaceId));
  return ref.watch(invoicesRepositoryProvider).invoices(spaceId);
});

final businessProfileProvider = FutureProvider.family<BusinessProfile?, String>(
  (ref, spaceId) {
    ref.watch(invoicesVersionProvider(spaceId));
    return ref.watch(invoicesRepositoryProvider).businessProfile(spaceId);
  },
);

final invoiceStatsProvider = FutureProvider.family<InvoiceStats, String>((
  ref,
  spaceId,
) {
  ref.watch(invoicesVersionProvider(spaceId));
  ref.watch(jobsVersionProvider(spaceId));
  return ref.watch(invoicesRepositoryProvider).stats(spaceId);
});

final itemsUsedProvider = FutureProvider.family<List<ItemUsage>, String>((
  ref,
  spaceId,
) {
  ref.watch(invoicesVersionProvider(spaceId));
  return ref.watch(invoicesRepositoryProvider).itemsUsedThisMonth(spaceId);
});

/// Billing changes the job's status and the customer's khata, which live in
/// other repositories. Call this after issuing, paying, or voiding so every
/// screen refreshes on the hosted backend too.
void refreshAfterBilling(WidgetRef ref, String spaceId, {String? jobId}) {
  ref.invalidate(jobsProvider(spaceId));
  if (jobId != null) {
    ref.invalidate(jobProvider((spaceId, jobId)));
    ref.invalidate(jobEventsProvider((spaceId, jobId)));
  }
  ref.invalidate(partyBalancesProvider(spaceId));
  ref.invalidate(spaceTotalsProvider(spaceId));
}
