import 'package:duebook/features/ledger/ledger_models.dart';
import 'package:duebook/features/ledger/ledger_repository.dart';
import 'package:duebook/features/ledger/statement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PreviewLedgerRepository repo;

  setUp(() => repo = PreviewLedgerRepository());

  test('sample data balances add up per party and per space', () async {
    final list = await repo.partiesWithBalances('p');
    final bilal = list.firstWhere((p) => p.party.name == 'Bilal Bhai');
    final shop = list.firstWhere((p) => p.party.name == 'Corner Shop');
    final sara = list.firstWhere((p) => p.party.name == 'Sara Apa');
    expect(bilal.balancePaisa, 300000); // gave 5000, got 2000
    expect(shop.balancePaisa, -150000);
    expect(sara.balancePaisa, 0);
    expect(sara.settled, isTrue);
    final t = await repo.totals('p');
    expect(t.willGetPaisa, 300000);
    expect(t.willGivePaisa, 150000);
  });

  test('adding entries moves the balance both ways', () async {
    final p = await repo.addParty('p', name: 'Test Person');
    await repo.addEntry(
      NewEntry(
        spaceId: 'p',
        partyId: p.id,
        direction: EntryDirection.gave,
        amountPaisa: 100000,
        entryDate: DateTime.now(),
      ),
    );
    await repo.addEntry(
      NewEntry(
        spaceId: 'p',
        partyId: p.id,
        direction: EntryDirection.got,
        amountPaisa: 40000,
        entryDate: DateTime.now(),
      ),
    );
    final pb = (await repo.partiesWithBalances('p'))
        .firstWhere((x) => x.party.id == p.id);
    expect(pb.balancePaisa, 60000);
    expect(pb.entryCount, 2);
  });

  test('voiding keeps the original struck through, adds a reversal, restores the balance', () async {
    final p = await repo.addParty('p', name: 'Void Test');
    final e = await repo.addEntry(
      NewEntry(
        spaceId: 'p',
        partyId: p.id,
        direction: EntryDirection.gave,
        amountPaisa: 250000,
        entryDate: DateTime.now(),
      ),
    );
    await repo.voidEntry(e.id, note: 'mistake');
    final entries = await repo.entriesForParty(p.id);
    expect(entries.length, 2);
    final original = entries.firstWhere((x) => x.id == e.id);
    final reversal = entries.firstWhere((x) => x.reversalOf == e.id);
    expect(original.isVoided, isTrue);
    expect(reversal.isReversal, isTrue);
    expect(reversal.direction, EntryDirection.got);
    expect(reversal.amountPaisa, 250000);
    final pb = (await repo.partiesWithBalances('p'))
        .firstWhere((x) => x.party.id == p.id);
    expect(pb.balancePaisa, 0);
    expect(pb.entryCount, 0);
    expect(() => repo.voidEntry(e.id), throwsStateError);
  });

  test(
    'editing an entry changes amount and note and marks it edited',
    () async {
      final p = await repo.addParty('p', name: 'Edit Test');
      final e = await repo.addEntry(
        NewEntry(
          spaceId: 'p',
          partyId: p.id,
          direction: EntryDirection.gave,
          amountPaisa: 100,
          entryDate: DateTime.now(),
          note: 'a',
        ),
      );
      final edited = await repo.editEntry(
        e.id,
        const EntryEdit(amountPaisa: 900, note: 'b'),
      );
      expect(edited.amountPaisa, 900);
      expect(edited.note, 'b');
      expect(edited.updatedAt, isNotNull);
    },
  );

  test('change stream fires for the right space only', () async {
    final seen = <void>[];
    final sub = repo.changes('p').listen(seen.add);
    await repo.addParty('f', name: 'Other space');
    await repo.addParty('p', name: 'This space');
    await Future<void>.delayed(Duration.zero);
    expect(seen.length, 1);
    await sub.cancel();
  });

  test('reminders list only open ones, soonest first', () async {
    final list = await repo.partiesWithBalances('p');
    final a = list[0].party.id;
    final r1 = await repo.setReminder(
      'p',
      a,
      DateTime.now().add(const Duration(days: 10)),
    );
    await repo.setReminder('p', a, DateTime.now().add(const Duration(days: 1)));
    var rs = await repo.reminders('p');
    expect(rs.first.dueDate.isBefore(rs.last.dueDate), isTrue);
    await repo.markReminderDone(r1.id);
    rs = await repo.reminders('p');
    expect(rs.any((r) => r.id == r1.id), isFalse);
  });

  test('CSV export is oldest first with a BOM and quoted notes', () async {
    final parties = {
      for (final pb in await repo.partiesWithBalances('p'))
        pb.party.id: pb.party,
    };
    final entries = await repo.entriesForSpace('p');
    final bytes = Statement.csv(entries: entries, parties: parties);
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    final text = String.fromCharCodes(bytes.sublist(3));
    final lines = text.trim().split('\n');
    expect(
      lines.first,
      'date,party,direction,amount_rupees,note,status,added_by',
    );
    expect(lines.length, entries.length + 1);
    final dates = lines.skip(1).map((l) => l.split(',').first).toList();
    expect(dates, List.of(dates)..sort());
    expect(
      text,
      contains('"Monthly groceries on credit"')
          .or(contains('Monthly groceries on credit')),
    );
  });
}

extension on Matcher {
  Matcher or(Matcher other) => anyOf(this, other);
}
