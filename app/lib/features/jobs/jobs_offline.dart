import '../../core/offline/offline_sync.dart';

/// The server row a new job will have, built on the phone while it waits.
/// [p] holds what the person chose plus the names to show.
Map<String, dynamic> pendingJobRow(Map<String, dynamic> p) => {
  'id': p['id'],
  'space_id': p['space_id'],
  'customer_id': p['customer_id'],
  'title': p['title'],
  'job_type': p['job_type'],
  'scheduled_at': p['scheduled_at'],
  'address': p['address'],
  'notes': p['notes'],
  'estimate_paisa': p['estimate_paisa'],
  'status': 'scheduled',
  'created_by': p['created_by'],
  'created_at': p['created_at'],
  'hold_reason': null,
  'hold_note': null,
  'suggested_at': null,
  'follow_up_of': p['follow_up_of'],
  'parties': {'name': p['customer_name'], 'phone_display': p['customer_phone']},
  'job_assignees': [
    for (final a in (p['assignees'] as List? ?? const []))
      {
        'user_id': (a as Map)['user_id'],
        'confirmed_at': null,
        'profiles': {'display_name': a['name']},
      },
  ],
};

/// The params for another visit, taken from the job it follows.
Map<String, dynamic> followUpParams({
  required Map<String, dynamic> base,
  required String id,
  required String scheduledAt,
  required String createdBy,
  String? title,
  String? notes,
}) => {
  'id': id,
  'job_id': base['id'],
  'space_id': base['space_id'],
  'customer_id': base['customer_id'],
  'title': (title == null || title.trim().isEmpty) ? base['title'] : title,
  'job_type': base['job_type'],
  'scheduled_at': scheduledAt,
  'address': base['address'],
  'notes': (notes == null || notes.trim().isEmpty) ? base['notes'] : notes,
  'estimate_paisa': null,
  'created_by': createdBy,
  'created_at': DateTime.now().toUtc().toIso8601String(),
  'follow_up_of': base['id'],
  'customer_name': (base['parties'] as Map?)?['name'],
  'customer_phone': (base['parties'] as Map?)?['phone_display'],
  'assignees': [
    for (final a in (base['job_assignees'] as List? ?? const []))
      {
        'user_id': (a as Map)['user_id'],
        'name': (a['profiles'] as Map?)?['display_name'],
      },
  ],
};

Map<String, dynamic> _patchJob(Map<String, dynamic> r, PendingChange c) {
  final p = c.params;
  switch (c.kind) {
    case 'jobs.confirm':
      return {
        ...r,
        if (r['status'] == 'scheduled') 'status': 'confirmed',
        'job_assignees': [
          for (final a in (r['job_assignees'] as List? ?? const []))
            (a as Map)['user_id'] == p['user_id']
                ? {...a, 'confirmed_at': a['confirmed_at'] ?? p['at']}
                : a,
        ],
      };
    case 'jobs.setStatus':
      return {...r, 'status': p['status']};
    case 'jobs.reportProblem':
      return {
        ...r,
        'status': 'on_hold',
        'hold_reason': p['reason'],
        'hold_note': p['note'],
        'suggested_at': p['suggested_at'],
      };
    case 'jobs.reschedule':
      return {
        ...r,
        'scheduled_at': p['scheduled_at'],
        if (const {
          'confirmed',
          'on_the_way',
          'working',
          'on_hold',
        }.contains(r['status']))
          'status': 'scheduled',
        'hold_reason': null,
        'hold_note': null,
        'suggested_at': null,
        'job_assignees': [
          for (final a in (r['job_assignees'] as List? ?? const []))
            {...(a as Map), 'confirmed_at': null},
        ],
      };
  }
  return r;
}

bool _inRange(String key, String scheduledAt) {
  // jobs:<space>|<from>|<to>, with empty parts when there is no limit.
  final parts = key.split('|');
  if (parts.length < 3) return true;
  final from = parts[1], to = parts[2];
  final at = DateTime.parse(scheduledAt);
  if (from.isNotEmpty && at.isBefore(DateTime.parse(from))) return false;
  if (to.isNotEmpty && !at.isBefore(DateTime.parse(to))) return false;
  return true;
}

/// Lays job changes that are still waiting over saved job data.
Object? jobsOverlay(String key, Object? data, PendingChange c) {
  final p = c.params;
  switch (c.kind) {
    case 'jobs.create':
    case 'jobs.followUp':
      final row = pendingJobRow(p);
      if (key == 'job:${p['id']}') return data ?? row;
      if (key.startsWith('jobs:${p['space_id']}|')) {
        final rows = offlineRows(data);
        if (rows.any((r) => r['id'] == p['id'])) return rows;
        if (!_inRange(key, p['scheduled_at'] as String)) return rows;
        return [...rows, row]..sort(
          (a, b) => (a['scheduled_at'] as String).compareTo(
            b['scheduled_at'] as String,
          ),
        );
      }
      return data;
    case 'jobs.confirm':
    case 'jobs.setStatus':
    case 'jobs.reportProblem':
    case 'jobs.reschedule':
      final id = p['job_id'];
      if (key == 'job:$id' && data is Map) {
        return _patchJob(Map<String, dynamic>.from(data), c);
      }
      if (key.startsWith('jobs:')) {
        return [
          for (final r in offlineRows(data))
            r['id'] == id ? _patchJob(r, c) : r,
        ];
      }
      return data;
    case 'jobs.setItems':
      if (key != 'job_items:${p['job_id']}') return data;
      return [
        for (final i in (p['items'] as List))
          {
            ...(i as Map<String, dynamic>),
            'items': {'unit': i['unit']},
          },
      ];
  }
  return data;
}
