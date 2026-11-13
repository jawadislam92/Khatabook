import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../../core/offline/offline_sync.dart';
import 'ledger_models.dart';
import 'ledger_offline.dart';

abstract class LedgerRepository {
  Future<List<PartyBalance>> partiesWithBalances(String spaceId);
  Future<SpaceTotals> totals(String spaceId);
  Future<Party> addParty(
    String spaceId, {
    required String name,
    String? phone,
    bool isCustomer = false,
  });
  Future<Party> updateParty(Party party);
  Future<List<Entry>> entriesForParty(String partyId);
  Future<List<Entry>> entriesForSpace(
    String spaceId, {
    DateTime? from,
    DateTime? to,
  });
  Future<Entry> addEntry(NewEntry entry);
  Future<Entry> editEntry(String entryId, EntryEdit edit);
  Future<void> voidEntry(String entryId, {String? note});
  Future<List<Reminder>> reminders(String spaceId);
  Future<Reminder> setReminder(
    String spaceId,
    String partyId,
    DateTime dueDate, {
    String? note,
  });
  Future<void> markReminderDone(String reminderId);

  /// Emits whenever something in the space changed, locally or remotely.
  Stream<void> changes(String spaceId);
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class SupabaseLedgerRepository implements LedgerRepository {
  SupabaseLedgerRepository(this._c, this._off) {
    _off.registerSender('ledger.addParty', _sendAddParty, done: isDuplicateKey);
    _off.registerSender('ledger.updateParty', _sendUpdateParty);
    _off.registerSender('ledger.addEntry', _sendAddEntry, done: isDuplicateKey);
    _off.registerSender(
      'ledger.setReminder',
      _sendSetReminder,
      done: isDuplicateKey,
    );
    _off.registerSender('ledger.reminderDone', _sendReminderDone);
    _off.registerOverlay(ledgerOverlay);
    _off.onSent(() => _local.add('*'));
  }
  final sb.SupabaseClient _c;
  final OfflineSync _off;
  final _local = StreamController<String>.broadcast();

  String get _me => _c.auth.currentUser?.id ?? '';
  String? get _myName =>
      _c.auth.currentUser?.userMetadata?['display_name'] as String?;

  Party _party(Map<String, dynamic> r) => Party(
    id: r['id'] as String,
    spaceId: r['space_id'] as String,
    name: r['name'] as String,
    phone: r['phone_display'] as String?,
    isCustomer: (r['is_customer'] as bool?) ?? false,
    address: r['address'] as String?,
    notes: r['notes'] as String?,
  );

  Entry _entry(Map<String, dynamic> r) => Entry(
    id: r['id'] as String,
    spaceId: r['space_id'] as String,
    bookId: r['book_id'] as String,
    partyId: r['party_id'] as String,
    direction: EntryDirection.values.byName(r['direction'] as String),
    amountPaisa: (r['amount_paisa'] as num).toInt(),
    entryDate: DateTime.parse(r['entry_date'] as String),
    note: r['note'] as String?,
    source: EntrySource.values.byName(r['source_type'] as String),
    reversalOf: r['reversal_of'] as String?,
    voidedAt: r['voided_at'] == null
        ? null
        : DateTime.parse(r['voided_at'] as String),
    createdBy: r['created_by'] as String,
    createdByName: (r['profiles'] as Map?)?['display_name'] as String?,
    createdAt: DateTime.parse(r['created_at'] as String),
    updatedAt: r['updated_at'] == null
        ? null
        : DateTime.parse(r['updated_at'] as String),
  );

  Reminder _reminder(Map<String, dynamic> r) => Reminder(
    id: r['id'] as String,
    spaceId: r['space_id'] as String,
    partyId: r['party_id'] as String,
    dueDate: DateTime.parse(r['due_date'] as String),
    note: r['note'] as String?,
    doneAt: r['done_at'] == null
        ? null
        : DateTime.parse(r['done_at'] as String),
  );

  Future<String> _defaultBook(String spaceId) async {
    final r = await _off.read(
      'book:$spaceId',
      () => _c
          .from('books')
          .select('id')
          .eq('space_id', spaceId)
          .eq('is_default', true)
          .single(),
    );
    return (r as Map)['id'] as String;
  }

  @override
  Future<List<PartyBalance>> partiesWithBalances(String spaceId) async {
    final parties = offlineRows(
      await _off.read(
        'parties:$spaceId',
        () => _c
            .from('parties')
            .select()
            .eq('space_id', spaceId)
            .isFilter('deleted_at', null)
            .order('name'),
      ),
    );
    final balances = offlineRows(
      await _off.read(
        'balances:$spaceId',
        () => _c.from('party_balances').select().eq('space_id', spaceId),
      ),
    );
    final byId = {for (final b in balances) b['party_id'] as String: b};
    return [
      for (final p in parties)
        PartyBalance(
          party: _party(p),
          balancePaisa: ((byId[p['id']]?['balance_paisa'] as num?) ?? 0)
              .toInt(),
          entryCount: ((byId[p['id']]?['entry_count'] as num?) ?? 0).toInt(),
          lastEntryDate: byId[p['id']]?['last_entry_date'] == null
              ? null
              : DateTime.parse(byId[p['id']]!['last_entry_date'] as String),
        ),
    ];
  }

  @override
  Future<SpaceTotals> totals(String spaceId) async {
    // Entries waiting to be sent change the totals: work them out from the
    // balances, which already include those entries.
    if (_off.pending.any(
      (c) =>
          !c.failed &&
          c.kind == 'ledger.addEntry' &&
          c.params['space_id'] == spaceId,
    )) {
      var get = 0, give = 0;
      for (final pb in await partiesWithBalances(spaceId)) {
        if (pb.balancePaisa > 0) get += pb.balancePaisa;
        if (pb.balancePaisa < 0) give -= pb.balancePaisa;
      }
      return SpaceTotals(willGetPaisa: get, willGivePaisa: give);
    }
    final r = await _off.read(
      'totals:$spaceId',
      () => _c
          .from('space_totals')
          .select()
          .eq('space_id', spaceId)
          .maybeSingle(),
    ) as Map?;
    if (r == null) return SpaceTotals.zero;
    return SpaceTotals(
      willGetPaisa: (r['will_get_paisa'] as num).toInt(),
      willGivePaisa: (r['will_give_paisa'] as num).toInt(),
    );
  }

  @override
  Future<Party> addParty(
    String spaceId, {
    required String name,
    String? phone,
    bool isCustomer = false,
  }) async {
    final row = {
      'id': const Uuid().v4(),
      'space_id': spaceId,
      'name': name.trim(),
      'phone_display': phone?.trim().isEmpty ?? true ? null : phone!.trim(),
      'is_customer': isCustomer,
      'created_by': _me,
    };
    final p = await _off.write<Party>(
      kind: 'ledger.addParty',
      params: row,
      now: () async =>
          _party(await _c.from('parties').insert(row).select().single()),
      later: () => _party(row),
    );
    _local.add(spaceId);
    return p;
  }

  Future<void> _sendAddParty(Map<String, dynamic> row) =>
      _c.from('parties').insert(row);

  @override
  Future<Party> updateParty(Party party) async {
    final params = {
      'id': party.id,
      'space_id': party.spaceId,
      'name': party.name.trim(),
      'phone_display': party.phone,
      'address': party.address,
      'notes': party.notes,
    };
    final p = await _off.write<Party>(
      kind: 'ledger.updateParty',
      params: params,
      now: () async => _party(
        await _c
            .from('parties')
            .update(_partyPatch(params))
            .eq('id', party.id)
            .select()
            .single(),
      ),
      later: () => party.copyWith(name: party.name.trim()),
    );
    _local.add(party.spaceId);
    return p;
  }

  static Map<String, dynamic> _partyPatch(Map<String, dynamic> p) => {
    'name': p['name'],
    'phone_display': p['phone_display'],
    'address': p['address'],
    'notes': p['notes'],
  };

  Future<void> _sendUpdateParty(Map<String, dynamic> p) =>
      _c.from('parties').update(_partyPatch(p)).eq('id', p['id'] as String);

  static const _entrySelect = '*, profiles:created_by(display_name)';

  @override
  Future<List<Entry>> entriesForParty(String partyId) async {
    final rows = offlineRows(
      await _off.read(
        'entries_party:$partyId',
        () => _c
            .from('entries')
            .select(_entrySelect)
            .eq('party_id', partyId)
            .order('entry_date', ascending: false)
            .order('created_at', ascending: false),
      ),
    );
    return [for (final r in rows) _entry(r)];
  }

  @override
  Future<List<Entry>> entriesForSpace(
    String spaceId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final key =
        'entries_space:$spaceId:${from == null ? '' : _date(from)}:${to == null ? '' : _date(to)}';
    final rows = offlineRows(
      await _off.read(key, () {
        var q = _c.from('entries').select(_entrySelect).eq('space_id', spaceId);
        if (from != null) q = q.gte('entry_date', _date(from));
        if (to != null) q = q.lte('entry_date', _date(to));
        return q
            .order('entry_date', ascending: false)
            .order('created_at', ascending: false);
      }),
    );
    return [for (final r in rows) _entry(r)];
  }

  @override
  Future<Entry> addEntry(NewEntry e) async {
    final params = {
      'id': const Uuid().v4(),
      'space_id': e.spaceId,
      'party_id': e.partyId,
      'direction': e.direction.name,
      'amount_paisa': e.amountPaisa,
      'entry_date': _date(e.entryDate),
      'note': e.note?.trim().isEmpty ?? true ? null : e.note!.trim(),
      'created_by': _me,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'created_by_name': _myName,
    };
    final entry = await _off.write<Entry>(
      kind: 'ledger.addEntry',
      params: params,
      now: () async {
        final book = await _defaultBook(e.spaceId);
        return _entry(
          await _c
              .from('entries')
              .insert(_entryInsert(params, book))
              .select(_entrySelect)
              .single(),
        );
      },
      later: () async {
        final book = await _off.saved('book:${e.spaceId}');
        return _entry(
          pendingEntryRow(params, book is Map ? book['id'] as String : ''),
        );
      },
    );
    _local.add(e.spaceId);
    return entry;
  }

  static Map<String, dynamic> _entryInsert(
    Map<String, dynamic> p,
    String book,
  ) => {
    'id': p['id'],
    'space_id': p['space_id'],
    'book_id': book,
    'party_id': p['party_id'],
    'direction': p['direction'],
    'amount_paisa': p['amount_paisa'],
    'entry_date': p['entry_date'],
    'note': p['note'],
    'created_by': p['created_by'],
  };

  Future<void> _sendAddEntry(Map<String, dynamic> p) async {
    final book = await _defaultBook(p['space_id'] as String);
    await _c.from('entries').insert(_entryInsert(p, book));
  }

  @override
  Future<Entry> editEntry(String entryId, EntryEdit edit) async {
    final patch = <String, dynamic>{};
    if (edit.amountPaisa != null) patch['amount_paisa'] = edit.amountPaisa;
    if (edit.direction != null) patch['direction'] = edit.direction!.name;
    if (edit.entryDate != null) patch['entry_date'] = _date(edit.entryDate!);
    if (edit.note != null) {
      patch['note'] = edit.note!.trim().isEmpty ? null : edit.note!.trim();
    }
    final r = await _c
        .from('entries')
        .update(patch)
        .eq('id', entryId)
        .select(_entrySelect)
        .single();
    final entry = _entry(r);
    _local.add(entry.spaceId);
    return entry;
  }

  @override
  Future<void> voidEntry(String entryId, {String? note}) async {
    await _c.rpc<String>(
      'void_entry',
      params: {'p_entry': entryId, 'p_note': note},
    );
    _local.add('*');
  }

  @override
  Future<List<Reminder>> reminders(String spaceId) async {
    final rows = offlineRows(
      await _off.read(
        'reminders:$spaceId',
        () => _c
            .from('reminders')
            .select()
            .eq('space_id', spaceId)
            .isFilter('done_at', null)
            .order('due_date'),
      ),
    );
    return [for (final r in rows) _reminder(r)];
  }

  @override
  Future<Reminder> setReminder(
    String spaceId,
    String partyId,
    DateTime dueDate, {
    String? note,
  }) async {
    final row = {
      'id': const Uuid().v4(),
      'space_id': spaceId,
      'party_id': partyId,
      'due_date': _date(dueDate),
      'note': note,
      'created_by': _me,
    };
    final r = await _off.write<Reminder>(
      kind: 'ledger.setReminder',
      params: row,
      now: () async =>
          _reminder(await _c.from('reminders').insert(row).select().single()),
      later: () => _reminder(row),
    );
    _local.add(spaceId);
    return r;
  }

  Future<void> _sendSetReminder(Map<String, dynamic> row) =>
      _c.from('reminders').insert(row);

  @override
  Future<void> markReminderDone(String reminderId) async {
    final params = {
      'id': reminderId,
      'done_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _off.write<void>(
      kind: 'ledger.reminderDone',
      params: params,
      now: () => _sendReminderDone(params),
      later: () {},
    );
    _local.add('*');
  }

  Future<void> _sendReminderDone(Map<String, dynamic> p) => _c
      .from('reminders')
      .update({'done_at': p['done_at']})
      .eq('id', p['id'] as String);

  @override
  Stream<void> changes(String spaceId) {
    // Local writes plus realtime changes from other members of the space.
    final controller = StreamController<void>.broadcast();
    final sub = _local.stream
        .where((s) => s == '*' || s == spaceId)
        .listen((_) => controller.add(null));
    final channel = _c
        .channel('space-$spaceId')
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.all,
          schema: 'public',
          table: 'entries',
          filter: sb.PostgresChangeFilter(
            type: sb.PostgresChangeFilterType.eq,
            column: 'space_id',
            value: spaceId,
          ),
          callback: (_) => controller.add(null),
        )
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.all,
          schema: 'public',
          table: 'parties',
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

/// Preview mode with sample data so the app is usable without a server.
class PreviewLedgerRepository implements LedgerRepository {
  PreviewLedgerRepository() {
    _seed();
  }

  final _uuid = const Uuid();
  final _parties = <Party>[];
  final _entries = <Entry>[];
  final _reminders = <Reminder>[];
  final _changes = StreamController<String>.broadcast();

  void _seed() {
    final today = DateTime.now();
    Party p(String space, String name, String? phone) {
      final party = Party(
        id: _uuid.v4(),
        spaceId: space,
        name: name,
        phone: phone,
      );
      _parties.add(party);
      return party;
    }

    void e(
      Party party,
      EntryDirection d,
      int rupees,
      int daysAgo,
      String? note,
    ) {
      _entries.add(
        Entry(
          id: _uuid.v4(),
          spaceId: party.spaceId,
          bookId: 'b-${party.spaceId}',
          partyId: party.id,
          direction: d,
          amountPaisa: rupees * 100,
          entryDate: today.subtract(Duration(days: daysAgo)),
          note: note,
          createdBy: 'preview',
          createdByName: 'You',
          createdAt: today.subtract(Duration(days: daysAgo)),
        ),
      );
    }

    final bilal = p('p', 'Bilal Bhai', '0300 1234567');
    final shop = p('p', 'Corner Shop', '0321 7654321');
    final sara = p('p', 'Sara Apa', null);
    e(bilal, EntryDirection.gave, 5000, 12, 'For motorbike repair');
    e(bilal, EntryDirection.got, 2000, 4, null);
    e(shop, EntryDirection.got, 1500, 9, 'Monthly groceries on credit');
    e(sara, EntryDirection.gave, 12000, 30, 'Wedding contribution');
    e(sara, EntryDirection.got, 12000, 2, 'Returned, thank you');

    final ahmed = p('f', 'Ahmed Mamu', '0333 1112223');
    final tailor = p('f', 'Rafiq Tailor', null);
    e(ahmed, EntryDirection.got, 25000, 20, 'Borrowed for school fees');
    e(ahmed, EntryDirection.gave, 10000, 6, 'Partly returned');
    e(tailor, EntryDirection.gave, 3500, 3, 'Advance for Eid clothes');

    final ahmedF10 = p('b', 'Mr Ahmed F-10', '0300 5556667');
    final khan = p('b', 'Khan Traders', '0321 9998887');
    p('b', 'Mrs Rizvi', '0333 4445556');
    e(ahmedF10, EntryDirection.gave, 4500, 1, 'Invoice INV-2026-0041 balance');
    e(khan, EntryDirection.gave, 185000, 15, 'Inverter supplied on credit');
    e(khan, EntryDirection.got, 100000, 7, 'Part payment, bank transfer');

    _reminders.add(
      Reminder(
        id: _uuid.v4(),
        spaceId: 'p',
        partyId: bilal.id,
        dueDate: today.add(const Duration(days: 3)),
      ),
    );
  }

  int _balance(String partyId) => _entries
      .where((e) => e.partyId == partyId)
      .fold(0, (s, e) => s + e.signedPaisa);

  @override
  Future<List<PartyBalance>> partiesWithBalances(String spaceId) async {
    final list = [
      for (final p in _parties.where((p) => p.spaceId == spaceId))
        PartyBalance(
          party: p,
          balancePaisa: _balance(p.id),
          entryCount: _entries
              .where((e) => e.partyId == p.id && !e.isVoided && !e.isReversal)
              .length,
          lastEntryDate: _entries
              .where((e) => e.partyId == p.id)
              .map((e) => e.entryDate)
              .fold<DateTime?>(
                null,
                (m, d) => m == null || d.isAfter(m) ? d : m,
              ),
        ),
    ];
    list.sort(
      (a, b) =>
          a.party.name.toLowerCase().compareTo(b.party.name.toLowerCase()),
    );
    return list;
  }

  @override
  Future<SpaceTotals> totals(String spaceId) async {
    var get = 0, give = 0;
    for (final p in _parties.where((p) => p.spaceId == spaceId)) {
      final b = _balance(p.id);
      if (b > 0) get += b;
      if (b < 0) give -= b;
    }
    return SpaceTotals(willGetPaisa: get, willGivePaisa: give);
  }

  @override
  Future<Party> addParty(
    String spaceId, {
    required String name,
    String? phone,
    bool isCustomer = false,
  }) async {
    final p = Party(
      id: _uuid.v4(),
      spaceId: spaceId,
      name: name.trim(),
      phone: phone,
      isCustomer: isCustomer,
    );
    _parties.add(p);
    _changes.add(spaceId);
    return p;
  }

  @override
  Future<Party> updateParty(Party party) async {
    final i = _parties.indexWhere((p) => p.id == party.id);
    _parties[i] = party;
    _changes.add(party.spaceId);
    return party;
  }

  List<Entry> _sorted(Iterable<Entry> it) {
    final l = it.toList();
    l.sort((a, b) {
      final d = b.entryDate.compareTo(a.entryDate);
      return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
    });
    return l;
  }

  @override
  Future<List<Entry>> entriesForParty(String partyId) async =>
      _sorted(_entries.where((e) => e.partyId == partyId));

  @override
  Future<List<Entry>> entriesForSpace(
    String spaceId, {
    DateTime? from,
    DateTime? to,
  }) async => _sorted(
    _entries.where(
      (e) =>
          e.spaceId == spaceId &&
          (from == null || !e.entryDate.isBefore(from)) &&
          (to == null || !e.entryDate.isAfter(to)),
    ),
  );

  @override
  Future<Entry> addEntry(NewEntry n) async {
    final e = Entry(
      id: _uuid.v4(),
      spaceId: n.spaceId,
      bookId: 'b-${n.spaceId}',
      partyId: n.partyId,
      direction: n.direction,
      amountPaisa: n.amountPaisa,
      entryDate: n.entryDate,
      note: n.note?.trim().isEmpty ?? true ? null : n.note!.trim(),
      createdBy: 'preview',
      createdByName: 'You',
      createdAt: DateTime.now(),
    );
    _entries.add(e);
    _changes.add(n.spaceId);
    return e;
  }

  @override
  Future<Entry> editEntry(String entryId, EntryEdit edit) async {
    final i = _entries.indexWhere((e) => e.id == entryId);
    final o = _entries[i];
    final n = Entry(
      id: o.id,
      spaceId: o.spaceId,
      bookId: o.bookId,
      partyId: o.partyId,
      direction: edit.direction ?? o.direction,
      amountPaisa: edit.amountPaisa ?? o.amountPaisa,
      entryDate: edit.entryDate ?? o.entryDate,
      note: edit.note == null
          ? o.note
          : (edit.note!.trim().isEmpty ? null : edit.note!.trim()),
      source: o.source,
      reversalOf: o.reversalOf,
      voidedAt: o.voidedAt,
      createdBy: o.createdBy,
      createdByName: o.createdByName,
      createdAt: o.createdAt,
      updatedAt: DateTime.now(),
    );
    _entries[i] = n;
    _changes.add(o.spaceId);
    return n;
  }

  @override
  Future<void> voidEntry(String entryId, {String? note}) async {
    final i = _entries.indexWhere((e) => e.id == entryId);
    final o = _entries[i];
    if (o.isVoided) throw StateError('already voided');
    _entries[i] = Entry(
      id: o.id,
      spaceId: o.spaceId,
      bookId: o.bookId,
      partyId: o.partyId,
      direction: o.direction,
      amountPaisa: o.amountPaisa,
      entryDate: o.entryDate,
      note: o.note,
      source: o.source,
      reversalOf: o.reversalOf,
      voidedAt: DateTime.now(),
      createdBy: o.createdBy,
      createdByName: o.createdByName,
      createdAt: o.createdAt,
      updatedAt: o.updatedAt,
    );
    _entries.add(
      Entry(
        id: _uuid.v4(),
        spaceId: o.spaceId,
        bookId: o.bookId,
        partyId: o.partyId,
        direction: o.direction == EntryDirection.gave
            ? EntryDirection.got
            : EntryDirection.gave,
        amountPaisa: o.amountPaisa,
        entryDate: DateTime.now(),
        note: note ?? 'Reversal',
        source: EntrySource.reversal,
        reversalOf: o.id,
        createdBy: 'preview',
        createdByName: 'You',
        createdAt: DateTime.now(),
      ),
    );
    _changes.add(o.spaceId);
  }

  @override
  Future<List<Reminder>> reminders(String spaceId) async {
    final l = _reminders
        .where((r) => r.spaceId == spaceId && !r.isDone)
        .toList();
    l.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return l;
  }

  @override
  Future<Reminder> setReminder(
    String spaceId,
    String partyId,
    DateTime dueDate, {
    String? note,
  }) async {
    final r = Reminder(
      id: _uuid.v4(),
      spaceId: spaceId,
      partyId: partyId,
      dueDate: dueDate,
      note: note,
    );
    _reminders.add(r);
    _changes.add(spaceId);
    return r;
  }

  @override
  Future<void> markReminderDone(String reminderId) async {
    final i = _reminders.indexWhere((r) => r.id == reminderId);
    final o = _reminders[i];
    _reminders[i] = Reminder(
      id: o.id,
      spaceId: o.spaceId,
      partyId: o.partyId,
      dueDate: o.dueDate,
      note: o.note,
      doneAt: DateTime.now(),
    );
    _changes.add(o.spaceId);
  }

  @override
  Stream<void> changes(String spaceId) =>
      _changes.stream.where((s) => s == '*' || s == spaceId);
}

final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) {
  if (AppConfig.isConfigured) {
    return SupabaseLedgerRepository(
      sb.Supabase.instance.client,
      ref.read(offlineSyncProvider),
    );
  }
  return PreviewLedgerRepository();
});

/// Bumps whenever the space's ledger changes, so dependent providers refetch.
final ledgerVersionProvider = StreamProvider.family<int, String>((
  ref,
  spaceId,
) {
  var n = 0;
  final controller = StreamController<int>();
  controller.add(0);
  final sub = ref
      .watch(ledgerRepositoryProvider)
      .changes(spaceId)
      .listen((_) => controller.add(++n));
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});

final partyBalancesProvider = FutureProvider.family<List<PartyBalance>, String>(
  (ref, spaceId) {
    ref.watch(ledgerVersionProvider(spaceId));
    return ref.watch(ledgerRepositoryProvider).partiesWithBalances(spaceId);
  },
);

final spaceTotalsProvider = FutureProvider.family<SpaceTotals, String>((
  ref,
  spaceId,
) {
  ref.watch(ledgerVersionProvider(spaceId));
  return ref.watch(ledgerRepositoryProvider).totals(spaceId);
});

final remindersProvider = FutureProvider.family<List<Reminder>, String>((
  ref,
  spaceId,
) {
  ref.watch(ledgerVersionProvider(spaceId));
  return ref.watch(ledgerRepositoryProvider).reminders(spaceId);
});

/// (spaceId, partyId)
final partyEntriesProvider =
    FutureProvider.family<List<Entry>, (String, String)>((ref, key) {
      ref.watch(ledgerVersionProvider(key.$1));
      return ref.watch(ledgerRepositoryProvider).entriesForParty(key.$2);
    });

final partyProvider = Provider.family<PartyBalance?, (String, String)>((
  ref,
  key,
) {
  final list = ref.watch(partyBalancesProvider(key.$1)).value;
  if (list == null) return null;
  for (final pb in list) {
    if (pb.party.id == key.$2) return pb;
  }
  return null;
});
