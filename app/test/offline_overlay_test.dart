// While changes wait to be sent, saved data must already show them:
// balances, totals, new people, job steps, new jobs and items.
import 'package:duebook/core/offline/offline_sync.dart';
import 'package:duebook/features/jobs/jobs_offline.dart';
import 'package:duebook/features/ledger/ledger_offline.dart';
import 'package:flutter_test/flutter_test.dart';

PendingChange _c(String kind, Map<String, dynamic> p) => PendingChange(
  id: 'x',
  kind: kind,
  params: p,
  createdAt: DateTime(2026, 11, 12),
);

Map<String, dynamic> _entry(String party, String dir, int amount) => {
  'id': 'e-$party-$amount',
  'space_id': 's',
  'party_id': party,
  'direction': dir,
  'amount_paisa': amount,
  'entry_date': '2026-11-12',
  'note': null,
  'created_by': 'u',
  'created_at': '2026-11-12T05:00:00Z',
  'created_by_name': 'QA',
};

void main() {
  group('ledger', () {
    test('a waiting entry moves the balance, count and date', () {
      final saved = [
        {
          'party_id': 'p1',
          'space_id': 's',
          'balance_paisa': 50000,
          'entry_count': 2,
          'last_entry_date': '2026-11-01',
        },
      ];
      var data = ledgerOverlay(
        'balances:s',
        saved,
        _c('ledger.addEntry', _entry('p1', 'got', 20000)),
      );
      data = ledgerOverlay(
        'balances:s',
        data,
        _c('ledger.addEntry', _entry('p2', 'gave', 7000)),
      );
      final rows = offlineRows(data);
      expect(rows.first['balance_paisa'], 30000);
      expect(rows.first['entry_count'], 3);
      expect(rows.first['last_entry_date'], '2026-11-12');
      expect(rows.last['party_id'], 'p2', reason: 'a person new on this phone');
      expect(rows.last['balance_paisa'], 7000);
    });

    test('a waiting entry shows first in the lists, once', () {
      final c = _c('ledger.addEntry', _entry('p1', 'gave', 500));
      final once = ledgerOverlay('entries_party:p1', [], c);
      final twice = ledgerOverlay('entries_party:p1', once, c);
      expect(offlineRows(twice), hasLength(1));
      expect(offlineRows(twice).single['source_type'], 'manual');
      expect(
        offlineRows(ledgerOverlay('entries_space:s::', [], c)),
        hasLength(1),
      );
      expect(ledgerOverlay('entries_party:p9', [], c), isEmpty);
    });

    test('a new person appears in name order', () {
      final data = ledgerOverlay(
        'parties:s',
        [
          {'id': 'a', 'space_id': 's', 'name': 'Ali'},
          {'id': 'z', 'space_id': 's', 'name': 'Zubair'},
        ],
        _c('ledger.addParty', {
          'id': 'n',
          'space_id': 's',
          'name': 'Bilal',
          'phone_display': null,
          'is_customer': false,
          'created_by': 'u',
        }),
      );
      expect(offlineRows(data).map((r) => r['name']), [
        'Ali',
        'Bilal',
        'Zubair',
      ]);
    });

    test('a reminder marked done disappears', () {
      final data = ledgerOverlay('reminders:s', [
        {'id': 'r1', 'due_date': '2026-11-20'},
        {'id': 'r2', 'due_date': '2026-11-21'},
      ], _c('ledger.reminderDone', {'id': 'r1', 'done_at': 'now'}));
      expect(offlineRows(data).map((r) => r['id']), ['r2']);
    });
  });

  group('jobs', () {
    final job = {
      'id': 'j1',
      'space_id': 's',
      'title': 'Install',
      'status': 'working',
      'scheduled_at': '2026-11-12T05:00:00.000Z',
      'customer_id': 'c',
      'job_type': 'cctv_install',
      'address': 'F-10',
      'notes': null,
      'parties': {'name': 'Mr Ahmed', 'phone_display': null},
      'job_assignees': [
        {
          'user_id': 'u',
          'confirmed_at': null,
          'profiles': {'display_name': 'Saeed'},
        },
      ],
    };

    test("Can't finish today shows on the job and in the lists", () {
      final c = _c('jobs.reportProblem', {
        'job_id': 'j1',
        'reason': 'no_power',
        'note': null,
        'suggested_at': null,
      });
      final one = ledgerSafe(jobsOverlay('job:j1', job, c));
      expect(one['status'], 'on_hold');
      expect(one['hold_reason'], 'no_power');
      final list = offlineRows(jobsOverlay('jobs:s||', [job], c));
      expect(list.single['status'], 'on_hold');
    });

    test('confirming marks me and moves a scheduled job on', () {
      final c = _c('jobs.confirm', {'job_id': 'j1', 'user_id': 'u', 'at': 't'});
      final r = ledgerSafe(
        jobsOverlay('job:j1', {...job, 'status': 'scheduled'}, c),
      );
      expect(r['status'], 'confirmed');
      expect((r['job_assignees'] as List).single['confirmed_at'], 't');
    });

    test('a new job made offline shows in a list that covers its day', () {
      final p = followUpParams(
        base: job,
        id: 'j2',
        scheduledAt: '2026-11-13T05:00:00.000Z',
        createdBy: 'u',
        title: 'One more camera',
      );
      final c = _c('jobs.followUp', p);
      final tomorrow = offlineRows(
        jobsOverlay(
          'jobs:s|2026-11-13T00:00:00.000Z|2026-11-14T00:00:00.000Z',
          [],
          c,
        ),
      );
      expect(tomorrow.single['title'], 'One more camera');
      expect(tomorrow.single['parties'], {
        'name': 'Mr Ahmed',
        'phone_display': null,
      });
      expect((tomorrow.single['job_assignees'] as List).single['user_id'], 'u');
      final today = offlineRows(
        jobsOverlay(
          'jobs:s|2026-11-12T00:00:00.000Z|2026-11-13T00:00:00.000Z',
          [],
          c,
        ),
      );
      expect(today, isEmpty, reason: 'not on the wrong day');
      expect(ledgerSafe(jobsOverlay('job:j2', null, c))['id'], 'j2');
    });

    test('items saved offline replace the saved list', () {
      final data = jobsOverlay(
        'job_items:j1',
        [
          {'id': 'old'},
        ],
        _c('jobs.setItems', {
          'job_id': 'j1',
          'space_id': 's',
          'items': [
            {
              'id': 'i1',
              'job_id': 'j1',
              'item_id': null,
              'description': 'Cable',
              'qty': 20,
              'unit': 'm',
              'unit_price_paisa': 6000,
              'note': null,
            },
          ],
        }),
      );
      final rows = offlineRows(data);
      expect(rows.single['description'], 'Cable');
      expect(rows.single['items'], {'unit': 'm'});
    });
  });
}

Map<String, dynamic> ledgerSafe(Object? d) =>
    Map<String, dynamic>.from(d as Map);
