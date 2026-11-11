import '../auth/auth_repository.dart';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../ledger/ledger_repository.dart';
import 'jobs_models.dart';

abstract class JobsRepository {
  Future<List<Job>> jobs(String spaceId, {DateTime? from, DateTime? to});
  Future<Job?> job(String jobId);
  Future<List<JobEvent>> events(String jobId);
  Future<String> createJob(NewJob job);
  Future<void> confirm(String jobId);
  Future<void> setStatus(String jobId, JobStatus status, {String? note});
  Future<void> reschedule(String jobId, DateTime at, {String? note});

  /// "Book another visit": a new job for the same customer and team at
  /// [at]. Returns the new job's id.
  Future<String> bookFollowUp(
    String jobId,
    DateTime at, {
    String? title,
    String? notes,
  });

  /// "Can't finish today". Every argument is optional.
  Future<void> reportProblem(
    String jobId, {
    String? reason,
    String? note,
    DateTime? suggestedAt,
  });
  Future<void> setAssignees(String jobId, List<String> userIds);
  Future<List<CatalogItem>> catalog(
    String spaceId, {
    bool includeInactive = false,
  });
  Future<CatalogItem> saveItem(CatalogItem item, {required bool isNew});
  Future<List<AppNotification>> notifications();
  Future<void> markRead(String id);
  Future<void> registerDevice(String token, String platform);
  Stream<void> changes(String spaceId);
}

String _ts(DateTime d) => d.toUtc().toIso8601String();

class SupabaseJobsRepository implements JobsRepository {
  SupabaseJobsRepository(this._c);
  final sb.SupabaseClient _c;
  final _local = StreamController<String>.broadcast();

  static const _select =
      '*, parties:customer_id(name, phone_display), job_assignees(user_id, confirmed_at, profiles:user_id(display_name))';

  Job _job(Map<String, dynamic> r) => Job(
    id: r['id'] as String,
    spaceId: r['space_id'] as String,
    customerId: r['customer_id'] as String,
    customerName: (r['parties'] as Map?)?['name'] as String? ?? '',
    customerPhone: (r['parties'] as Map?)?['phone_display'] as String?,
    title: r['title'] as String,
    type: JobTypeDb.fromDb(r['job_type'] as String),
    scheduledAt: DateTime.parse(r['scheduled_at'] as String).toLocal(),
    address: r['address'] as String?,
    notes: r['notes'] as String?,
    estimatePaisa: (r['estimate_paisa'] as num?)?.toInt(),
    status: JobStatusDb.fromDb(r['status'] as String),
    assignees: [
      for (final a in (r['job_assignees'] as List? ?? const []))
        JobAssignee(
          userId: a['user_id'] as String,
          name: (a['profiles'] as Map?)?['display_name'] as String? ?? '',
          confirmedAt: a['confirmed_at'] == null
              ? null
              : DateTime.parse(a['confirmed_at'] as String),
        ),
    ],
    createdBy: r['created_by'] as String,
    createdAt: DateTime.parse(r['created_at'] as String),
    holdReason: r['hold_reason'] as String?,
    holdNote: r['hold_note'] as String?,
    suggestedAt: r['suggested_at'] == null
        ? null
        : DateTime.parse(r['suggested_at'] as String).toLocal(),
  );

  @override
  Future<List<Job>> jobs(String spaceId, {DateTime? from, DateTime? to}) async {
    var q = _c.from('jobs').select(_select).eq('space_id', spaceId);
    if (from != null) q = q.gte('scheduled_at', _ts(from));
    if (to != null) q = q.lt('scheduled_at', _ts(to));
    final rows = await q.order('scheduled_at');
    return [for (final r in rows) _job(r)];
  }

  @override
  Future<Job?> job(String jobId) async {
    final r = await _c
        .from('jobs')
        .select(_select)
        .eq('id', jobId)
        .maybeSingle();
    return r == null ? null : _job(r);
  }

  @override
  Future<List<JobEvent>> events(String jobId) async {
    final rows = await _c
        .from('job_events')
        .select('*, profiles:actor_id(display_name)')
        .eq('job_id', jobId)
        .order('at');
    return [
      for (final r in rows)
        JobEvent(
          at: DateTime.parse(r['at'] as String),
          type: r['event_type'] as String,
          fromStatus: r['from_status'] == null
              ? null
              : JobStatusDb.fromDb(r['from_status'] as String),
          toStatus: r['to_status'] == null
              ? null
              : JobStatusDb.fromDb(r['to_status'] as String),
          actorName: (r['profiles'] as Map?)?['display_name'] as String?,
          note: r['note'] as String?,
        ),
    ];
  }

  @override
  Future<String> createJob(NewJob j) async {
    final id = await _c.rpc<String>(
      'create_job',
      params: {
        'p_space': j.spaceId,
        'p_customer': j.customerId,
        'p_title': j.title.trim(),
        'p_type': j.type.db,
        'p_scheduled_at': _ts(j.scheduledAt),
        'p_assignees': j.assigneeIds,
        'p_address': j.address,
        'p_notes': j.notes,
        'p_estimate_paisa': j.estimatePaisa,
      },
    );
    _local.add(j.spaceId);
    return id;
  }

  @override
  Future<void> confirm(String jobId) async {
    await _c.rpc<void>('confirm_job', params: {'p_job': jobId});
    _local.add('*');
  }

  @override
  Future<void> setStatus(String jobId, JobStatus status, {String? note}) async {
    await _c.rpc<void>(
      'set_job_status',
      params: {'p_job': jobId, 'p_status': status.db, 'p_note': note},
    );
    _local.add('*');
  }

  @override
  Future<void> reschedule(String jobId, DateTime at, {String? note}) async {
    await _c.rpc<void>(
      'reschedule_job',
      params: {'p_job': jobId, 'p_scheduled_at': _ts(at), 'p_note': note},
    );
    _local.add('*');
  }

  @override
  Future<String> bookFollowUp(
    String jobId,
    DateTime at, {
    String? title,
    String? notes,
  }) async {
    final id = await _c.rpc<String>(
      'book_follow_up',
      params: {
        'p_job': jobId,
        'p_scheduled_at': _ts(at),
        'p_title': title,
        'p_notes': notes,
      },
    );
    _local.add('*');
    return id;
  }

  @override
  Future<void> reportProblem(
    String jobId, {
    String? reason,
    String? note,
    DateTime? suggestedAt,
  }) async {
    await _c.rpc<void>(
      'report_job_problem',
      params: {
        'p_job': jobId,
        'p_reason': reason,
        'p_note': note,
        'p_suggested_at': suggestedAt == null ? null : _ts(suggestedAt),
      },
    );
    _local.add('*');
  }

  @override
  Future<void> setAssignees(String jobId, List<String> userIds) async {
    await _c.rpc<void>(
      'set_job_assignees',
      params: {'p_job': jobId, 'p_assignees': userIds},
    );
    _local.add('*');
  }

  CatalogItem _item(Map<String, dynamic> r) => CatalogItem(
    id: r['id'] as String,
    spaceId: r['space_id'] as String,
    nameEn: r['name_en'] as String,
    nameUr: r['name_ur'] as String?,
    unit: r['unit'] as String,
    category: r['category'] as String,
    salePricePaisa: (r['sale_price_paisa'] as num).toInt(),
    costPricePaisa: (r['cost_price_paisa'] as num?)?.toInt(),
    isFavourite: r['is_favourite'] as bool,
    allowPriceEdit: r['allow_price_edit'] as bool,
    active: r['active'] as bool,
  );

  @override
  Future<List<CatalogItem>> catalog(
    String spaceId, {
    bool includeInactive = false,
  }) async {
    var q = _c.from('items_visible').select().eq('space_id', spaceId);
    if (!includeInactive) q = q.eq('active', true);
    final rows = await q
        .order('is_favourite', ascending: false)
        .order('sort_order')
        .order('name_en');
    return [for (final r in rows) _item(r)];
  }

  @override
  Future<CatalogItem> saveItem(CatalogItem item, {required bool isNew}) async {
    final data = {
      'space_id': item.spaceId,
      'name_en': item.nameEn.trim(),
      'name_ur': item.nameUr?.trim().isEmpty ?? true
          ? null
          : item.nameUr!.trim(),
      'unit': item.unit,
      'category': item.category,
      'sale_price_paisa': item.salePricePaisa,
      'cost_price_paisa': item.costPricePaisa,
      'is_favourite': item.isFavourite,
      'allow_price_edit': item.allowPriceEdit,
      'active': item.active,
    };
    if (isNew) {
      data['created_by'] = _c.auth.currentUser!.id;
      final r = await _c.from('items').insert(data).select('id').single();
      _local.add(item.spaceId);
      final saved = await _c
          .from('items_visible')
          .select()
          .eq('id', r['id'] as String)
          .single();
      return _item(saved);
    }
    // Someone who cannot see cost prices gets null for them; saving that
    // back would wipe the owner's cost, so leave the column alone.
    if (item.costPricePaisa == null) data.remove('cost_price_paisa');
    await _c.from('items').update(data).eq('id', item.id);
    _local.add(item.spaceId);
    final saved = await _c
        .from('items_visible')
        .select()
        .eq('id', item.id)
        .single();
    return _item(saved);
  }

  @override
  Future<List<AppNotification>> notifications() async {
    final rows = await _c
        .from('notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return [
      for (final r in rows)
        AppNotification(
          id: r['id'] as String,
          kind: r['kind'] as String,
          title: r['title'] as String,
          body: r['body'] as String,
          deepLink: r['deep_link'] as String?,
          createdAt: DateTime.parse(r['created_at'] as String),
          readAt: r['read_at'] == null
              ? null
              : DateTime.parse(r['read_at'] as String),
        ),
    ];
  }

  @override
  Future<void> markRead(String id) => _c
      .from('notifications')
      .update({'read_at': _ts(DateTime.now())})
      .eq('id', id);

  @override
  Future<void> registerDevice(String token, String platform) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return;
    await _c.from('devices').upsert({
      'user_id': uid,
      'fcm_token': token,
      'platform': platform,
      'app_version': AppConfig.appVersion,
      'last_seen_at': _ts(DateTime.now()),
    }, onConflict: 'fcm_token');
  }

  @override
  Stream<void> changes(String spaceId) {
    final controller = StreamController<void>.broadcast();
    final sub = _local.stream
        .where((s) => s == '*' || s == spaceId)
        .listen((_) => controller.add(null));
    final channel = _c
        .channel('jobs-$spaceId')
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.all,
          schema: 'public',
          table: 'jobs',
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
          table: 'job_assignees',
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

/// Preview mode: sample jobs for the sample business space.
class PreviewJobsRepository implements JobsRepository {
  PreviewJobsRepository(this._ledger) {
    ready = _seed();
  }
  final LedgerRepository _ledger;

  /// Completes once the sample data is in place.
  late final Future<void> ready;
  final _uuid = const Uuid();
  final _jobs = <Job>[];
  final _events = <String, List<JobEvent>>{};
  final _items = <CatalogItem>[];
  final _notifs = <AppNotification>[];
  final _changes = StreamController<String>.broadcast();

  Future<void> _seed() async {
    final parties = await _ledger.partiesWithBalances('b');
    String cid(String name) =>
        parties.where((p) => p.party.name == name).firstOrNull?.party.id ?? '';
    final now = DateTime.now();
    final at = DateTime(now.year, now.month, now.day);
    Job mk(
      String title,
      JobType t,
      DateTime when,
      JobStatus s,
      String cust,
      List<JobAssignee> who, {
      String? addr,
    }) => Job(
      id: _uuid.v4(),
      spaceId: 'b',
      customerId: cid(cust),
      customerName: cust,
      customerPhone: '0300 5556667',
      title: title,
      type: t,
      scheduledAt: when,
      status: s,
      assignees: who,
      createdBy: 'u5',
      createdAt: now.subtract(const Duration(days: 1)),
      address: addr,
    );
    final saeed = JobAssignee(userId: 'u6', name: 'Saeed', confirmedAt: now);
    final bilal = JobAssignee(userId: 'u7', name: 'Bilal');
    const me = JobAssignee(userId: 'preview', name: 'You');
    _jobs.addAll([
      mk(
        '2 cameras not recording',
        JobType.cctvRepair,
        at.add(const Duration(hours: 10)),
        JobStatus.confirmed,
        'Mr Ahmed F-10',
        [saeed, bilal],
        addr: 'House 12, Street 4, F-10/2',
      ),
      mk(
        '5 kW solar service',
        JobType.solarService,
        at.add(const Duration(hours: 14)),
        JobStatus.scheduled,
        'Khan Traders',
        [me],
        addr: 'Blue Area, Plot 7',
      ),
      mk(
        'New 8 camera install',
        JobType.cctvInstall,
        at.add(const Duration(days: 1, hours: 11)),
        JobStatus.scheduled,
        'Mrs Rizvi',
        [bilal, me],
        addr: 'G-11/3, House 45',
      ),
      mk(
        'DVR replacement',
        JobType.cctvRepair,
        at.subtract(const Duration(days: 1)).add(const Duration(hours: 16)),
        JobStatus.finished,
        'Mr Ahmed F-10',
        [saeed],
      ),
    ]);
    for (final j in _jobs) {
      _events[j.id] = [
        JobEvent(
          at: j.createdAt,
          type: 'created',
          toStatus: JobStatus.scheduled,
          actorName: 'Ahmed Mamu',
        ),
      ];
    }
    CatalogItem it(
      String en,
      String ur,
      String unit,
      String cat,
      int sale,
      int cost, {
      bool fav = false,
      bool edit = false,
    }) => CatalogItem(
      id: _uuid.v4(),
      spaceId: 'b',
      nameEn: en,
      nameUr: ur,
      unit: unit,
      category: cat,
      salePricePaisa: sale * 100,
      costPricePaisa: cost * 100,
      isFavourite: fav,
      allowPriceEdit: edit,
    );
    _items.addAll([
      it(
        'Dome camera 2MP',
        'ڈوم کیمرہ 2MP',
        'pc',
        'camera',
        4500,
        3200,
        fav: true,
      ),
      it(
        'Bullet camera 5MP',
        'بلٹ کیمرہ 5MP',
        'pc',
        'camera',
        7800,
        5600,
        fav: true,
      ),
      it('8 channel DVR', '8 چینل DVR', 'pc', 'dvr', 16500, 12800),
      it('Coaxial cable', 'کوایکسل کیبل', 'm', 'cable', 45, 30, fav: true),
      it('BNC connector', 'BNC کنیکٹر', 'pc', 'accessory', 60, 35),
      it('Power supply 12V', 'پاور سپلائی 12V', 'pc', 'accessory', 1200, 850),
      it(
        'Solar panel 550W',
        'سولر پینل 550W',
        'pc',
        'solar_panel',
        24500,
        21000,
      ),
      it(
        'Hybrid inverter 5kW',
        'ہائبرڈ انورٹر 5kW',
        'pc',
        'inverter',
        185000,
        162000,
      ),
      it(
        'Service charge',
        'سروس چارج',
        'visit',
        'labour',
        1500,
        0,
        fav: true,
        edit: true,
      ),
      it(
        'Installation labour',
        'انسٹالیشن مزدوری',
        'hour',
        'labour',
        800,
        0,
        edit: true,
      ),
    ]);
    _notifs.addAll([
      AppNotification(
        id: _uuid.v4(),
        kind: 'job_assigned',
        title: 'New job',
        body:
            'Khan Traders: 5 kW solar service, today 2:00 pm. Tap to confirm.',
        createdAt: now.subtract(const Duration(hours: 3)),
        deepLink: '/space/b/job/${_jobs[1].id}',
      ),
      AppNotification(
        id: _uuid.v4(),
        kind: 'job_status',
        title: 'Job update',
        body: 'Saeed confirmed: Mr Ahmed F-10',
        createdAt: now.subtract(const Duration(hours: 5)),
        readAt: now,
        deepLink: '/space/b/job/${_jobs[0].id}',
      ),
    ]);
    _changes.add('b');
  }

  @override
  Future<List<Job>> jobs(String spaceId, {DateTime? from, DateTime? to}) async {
    final l = _jobs
        .where(
          (j) =>
              j.spaceId == spaceId &&
              (from == null || !j.scheduledAt.isBefore(from)) &&
              (to == null || j.scheduledAt.isBefore(to)),
        )
        .toList();
    l.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return l;
  }

  @override
  Future<Job?> job(String jobId) async =>
      _jobs.where((j) => j.id == jobId).firstOrNull;

  @override
  Future<List<JobEvent>> events(String jobId) async =>
      List.of(_events[jobId] ?? const []);

  void _replace(Job j) {
    final i = _jobs.indexWhere((x) => x.id == j.id);
    _jobs[i] = j;
    _changes.add(j.spaceId);
  }

  @override
  Future<String> createJob(NewJob n) async {
    final parties = await _ledger.partiesWithBalances(n.spaceId);
    final p = parties.firstWhere((x) => x.party.id == n.customerId);
    final members = {
      'preview': 'You',
      'u5': 'Ahmed Mamu',
      'u6': 'Saeed',
      'u7': 'Bilal',
      'u8': 'Munshi',
    };
    final j = Job(
      id: _uuid.v4(),
      spaceId: n.spaceId,
      customerId: n.customerId,
      customerName: p.party.name,
      customerPhone: p.party.phone,
      title: n.title.trim(),
      type: n.type,
      scheduledAt: n.scheduledAt,
      address: n.address,
      notes: n.notes,
      estimatePaisa: n.estimatePaisa,
      status: JobStatus.scheduled,
      assignees: [
        for (final id in n.assigneeIds)
          JobAssignee(userId: id, name: members[id] ?? id),
      ],
      createdBy: 'preview',
      createdAt: DateTime.now(),
    );
    _jobs.add(j);
    _events[j.id] = [
      JobEvent(
        at: j.createdAt,
        type: 'created',
        toStatus: JobStatus.scheduled,
        actorName: 'You',
      ),
    ];
    _changes.add(n.spaceId);
    return j.id;
  }

  @override
  Future<void> confirm(String jobId) async {
    final j = (await job(jobId))!;
    _replace(
      j.copyWith(
        status: j.status == JobStatus.scheduled
            ? JobStatus.confirmed
            : j.status,
        assignees: [
          for (final a in j.assignees)
            a.userId == 'preview'
                ? JobAssignee(
                    userId: a.userId,
                    name: a.name,
                    confirmedAt: DateTime.now(),
                  )
                : a,
        ],
      ),
    );
    _events[jobId]!.add(
      JobEvent(
        at: DateTime.now(),
        type: 'confirmed',
        fromStatus: JobStatus.scheduled,
        toStatus: JobStatus.confirmed,
        actorName: 'You',
      ),
    );
  }

  @override
  Future<void> setStatus(String jobId, JobStatus status, {String? note}) async {
    final j = (await job(jobId))!;
    _events[jobId]!.add(
      JobEvent(
        at: DateTime.now(),
        type: 'status',
        fromStatus: j.status,
        toStatus: status,
        actorName: 'You',
        note: note,
      ),
    );
    _replace(j.copyWith(status: status));
  }

  @override
  Future<void> reschedule(String jobId, DateTime at, {String? note}) async {
    final j = (await job(jobId))!;
    _events[jobId]!.add(
      JobEvent(
        at: DateTime.now(),
        type: 'rescheduled',
        actorName: 'You',
        note: note,
      ),
    );
    _replace(
      j.copyWith(
        scheduledAt: at,
        status: JobStatus.scheduled,
        assignees: [
          for (final a in j.assignees)
            JobAssignee(userId: a.userId, name: a.name),
        ],
      ),
    );
  }

  @override
  Future<String> bookFollowUp(
    String jobId,
    DateTime at, {
    String? title,
    String? notes,
  }) async {
    final j = (await job(jobId))!;
    final t = title?.trim() ?? '';
    final n = Job(
      id: _uuid.v4(),
      spaceId: j.spaceId,
      customerId: j.customerId,
      customerName: j.customerName,
      customerPhone: j.customerPhone,
      title: t.isEmpty ? j.title : t,
      type: j.type,
      scheduledAt: at,
      address: j.address,
      notes: (notes?.trim().isEmpty ?? true) ? j.notes : notes!.trim(),
      status: JobStatus.scheduled,
      assignees: [
        for (final a in j.assignees)
          JobAssignee(userId: a.userId, name: a.name),
      ],
      createdBy: 'preview',
      createdAt: DateTime.now(),
    );
    _jobs.add(n);
    _events[n.id] = [
      JobEvent(
        at: n.createdAt,
        type: 'created',
        toStatus: JobStatus.scheduled,
        actorName: 'You',
      ),
    ];
    _events[jobId]!.add(
      JobEvent(at: DateTime.now(), type: 'follow_up', actorName: 'You'),
    );
    _changes.add(j.spaceId);
    return n.id;
  }

  @override
  Future<void> reportProblem(
    String jobId, {
    String? reason,
    String? note,
    DateTime? suggestedAt,
  }) async {
    final j = (await job(jobId))!;
    _events[jobId]!.add(
      JobEvent(
        at: DateTime.now(),
        type: 'on_hold',
        fromStatus: j.status,
        toStatus: JobStatus.onHold,
        actorName: 'You',
        note: [reason, note].whereType<String>().join(' | '),
      ),
    );
    _replace(j.onHoldWith(reason: reason, note: note, suggested: suggestedAt));
  }

  @override
  Future<void> setAssignees(String jobId, List<String> userIds) async {
    final members = {
      'preview': 'You',
      'u5': 'Ahmed Mamu',
      'u6': 'Saeed',
      'u7': 'Bilal',
      'u8': 'Munshi',
    };
    final j = (await job(jobId))!;
    _replace(
      j.copyWith(
        assignees: [
          for (final id in userIds)
            j.assignees.where((a) => a.userId == id).firstOrNull ??
                JobAssignee(userId: id, name: members[id] ?? id),
        ],
      ),
    );
  }

  @override
  Future<List<CatalogItem>> catalog(
    String spaceId, {
    bool includeInactive = false,
  }) async =>
      _items
          .where((i) => i.spaceId == spaceId && (includeInactive || i.active))
          .toList()
        ..sort((a, b) => (b.isFavourite ? 1 : 0) - (a.isFavourite ? 1 : 0));

  @override
  Future<CatalogItem> saveItem(CatalogItem item, {required bool isNew}) async {
    final saved = isNew
        ? CatalogItem(
            id: _uuid.v4(),
            spaceId: item.spaceId,
            nameEn: item.nameEn,
            nameUr: item.nameUr,
            unit: item.unit,
            category: item.category,
            salePricePaisa: item.salePricePaisa,
            costPricePaisa: item.costPricePaisa,
            isFavourite: item.isFavourite,
            allowPriceEdit: item.allowPriceEdit,
            active: item.active,
          )
        : item;
    if (isNew) {
      _items.add(saved);
    } else {
      _items[_items.indexWhere((i) => i.id == item.id)] = saved;
    }
    _changes.add(item.spaceId);
    return saved;
  }

  @override
  Future<List<AppNotification>> notifications() async => List.of(_notifs);

  @override
  Future<void> markRead(String id) async {
    final i = _notifs.indexWhere((n) => n.id == id);
    final n = _notifs[i];
    _notifs[i] = AppNotification(
      id: n.id,
      kind: n.kind,
      title: n.title,
      body: n.body,
      createdAt: n.createdAt,
      deepLink: n.deepLink,
      readAt: DateTime.now(),
    );
    _changes.add('*');
  }

  @override
  Future<void> registerDevice(String token, String platform) async {}

  @override
  Stream<void> changes(String spaceId) =>
      _changes.stream.where((s) => s == '*' || s == spaceId);
}

final jobsRepositoryProvider = Provider<JobsRepository>((ref) {
  if (AppConfig.isConfigured) {
    return SupabaseJobsRepository(sb.Supabase.instance.client);
  }
  return PreviewJobsRepository(ref.watch(ledgerRepositoryProvider));
});

final jobsVersionProvider = StreamProvider.family<int, String>((ref, spaceId) {
  var n = 0;
  final c = StreamController<int>();
  c.add(0);
  final sub = ref
      .watch(jobsRepositoryProvider)
      .changes(spaceId)
      .listen((_) => c.add(++n));
  ref.onDispose(() {
    sub.cancel();
    c.close();
  });
  return c.stream;
});

final jobsProvider = FutureProvider.family<List<Job>, String>((ref, spaceId) {
  ref.watch(jobsVersionProvider(spaceId));
  return ref.watch(jobsRepositoryProvider).jobs(spaceId);
});

final jobProvider = FutureProvider.family<Job?, (String, String)>((ref, key) {
  ref.watch(jobsVersionProvider(key.$1));
  return ref.watch(jobsRepositoryProvider).job(key.$2);
});

final jobEventsProvider =
    FutureProvider.family<List<JobEvent>, (String, String)>((ref, key) {
      ref.watch(jobsVersionProvider(key.$1));
      return ref.watch(jobsRepositoryProvider).events(key.$2);
    });

final catalogProvider = FutureProvider.family<List<CatalogItem>, String>((
  ref,
  spaceId,
) {
  ref.watch(jobsVersionProvider(spaceId));
  return ref
      .watch(jobsRepositoryProvider)
      .catalog(spaceId, includeInactive: true);
});

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  ref.watch(currentUserProvider.select((u) => u.value?.id));
  ref.watch(jobsVersionProvider('*'));
  return ref.watch(jobsRepositoryProvider).notifications();
});
