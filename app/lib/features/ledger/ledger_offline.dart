import '../../core/offline/offline_sync.dart';

/// The server row an entry will have, built on the phone while it waits.
Map<String, dynamic> pendingEntryRow(Map<String, dynamic> p, String bookId) => {
  'id': p['id'],
  'space_id': p['space_id'],
  'book_id': bookId,
  'party_id': p['party_id'],
  'direction': p['direction'],
  'amount_paisa': p['amount_paisa'],
  'entry_date': p['entry_date'],
  'note': p['note'],
  'source_type': 'manual',
  'reversal_of': null,
  'voided_at': null,
  'created_by': p['created_by'],
  'created_at': p['created_at'],
  'updated_at': null,
  'profiles': {'display_name': p['created_by_name']},
};

bool _has(List<Map<String, dynamic>> rows, Object? id) =>
    rows.any((r) => r['id'] == id);

/// Lays ledger changes that are still waiting over saved ledger data, so
/// people, entries, balances and reminders show them at once.
Object? ledgerOverlay(String key, Object? data, PendingChange c) {
  final p = c.params;
  final space = p['space_id'];
  switch (c.kind) {
    case 'ledger.addParty':
      if (key != 'parties:$space') return data;
      final rows = offlineRows(data);
      if (_has(rows, p['id'])) return rows;
      rows.add({...p, 'address': null, 'notes': null, 'deleted_at': null});
      rows.sort(
        (a, b) => (a['name'] as String).toLowerCase().compareTo(
          (b['name'] as String).toLowerCase(),
        ),
      );
      return rows;
    case 'ledger.updateParty':
      if (key != 'parties:$space') return data;
      return [
        for (final r in offlineRows(data))
          r['id'] == p['id']
              ? {
                  ...r,
                  'name': p['name'],
                  'phone_display': p['phone_display'],
                  'address': p['address'],
                  'notes': p['notes'],
                }
              : r,
      ];
    case 'ledger.addEntry':
      if (key == 'entries_party:${p['party_id']}' ||
          key.startsWith('entries_space:$space:')) {
        final rows = offlineRows(data);
        if (_has(rows, p['id'])) return rows;
        return [pendingEntryRow(p, ''), ...rows];
      }
      if (key == 'balances:$space') {
        final rows = offlineRows(data);
        final amount =
            (p['amount_paisa'] as num).toInt() *
            (p['direction'] == 'gave' ? 1 : -1);
        final i = rows.indexWhere((r) => r['party_id'] == p['party_id']);
        if (i < 0) {
          rows.add({
            'party_id': p['party_id'],
            'space_id': space,
            'balance_paisa': amount,
            'entry_count': 1,
            'last_entry_date': p['entry_date'],
          });
        } else {
          final r = rows[i];
          final last = r['last_entry_date'] as String?;
          final date = p['entry_date'] as String;
          rows[i] = {
            ...r,
            'balance_paisa': ((r['balance_paisa'] as num?) ?? 0) + amount,
            'entry_count': ((r['entry_count'] as num?) ?? 0) + 1,
            'last_entry_date': last == null || date.compareTo(last) > 0
                ? date
                : last,
          };
        }
        return rows;
      }
      return data;
    case 'ledger.setReminder':
      if (key != 'reminders:$space') return data;
      final rows = offlineRows(data);
      if (_has(rows, p['id'])) return rows;
      return [
        ...rows,
        {...p, 'done_at': null},
      ]..sort(
        (a, b) => (a['due_date'] as String).compareTo(b['due_date'] as String),
      );
    case 'ledger.reminderDone':
      if (!key.startsWith('reminders:')) return data;
      return [
        for (final r in offlineRows(data))
          if (r['id'] != p['id']) r,
      ];
  }
  return data;
}
