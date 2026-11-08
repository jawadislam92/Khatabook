import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/config/app_config.dart';
import '../ledger/ledger_repository.dart';
import '../spaces/spaces_repository.dart';
import 'groups_models.dart';

abstract class GroupsRepository {
  Future<List<Member>> members(String spaceId);
  Future<List<ActivityItem>> activity(String spaceId, {int limit = 100});
  Future<String> createInviteToken(String spaceId, MemberRole role);
  Future<InvitePreview?> previewInvite(String token);
  Future<String> acceptInvite(String token);
  Future<void> changeRole(String spaceId, String userId, MemberRole role);
  Future<void> removeMember(String spaceId, String userId);
  Future<void> leave(String spaceId);
  Future<DateTime?> lockedUntil(String spaceId);
  Future<void> setLock(String spaceId, DateTime? until);
}

class SupabaseGroupsRepository implements GroupsRepository {
  SupabaseGroupsRepository(this._c);
  final sb.SupabaseClient _c;

  @override
  Future<List<Member>> members(String spaceId) async {
    final rows = await _c
        .from('space_member_stats')
        .select()
        .eq('space_id', spaceId)
        .order('joined_at');
    return [
      for (final r in rows)
        Member(
          userId: r['user_id'] as String,
          name: (r['display_name'] as String?) ?? '',
          role: MemberRole.values.byName(r['role'] as String),
          joinedAt: DateTime.parse(r['joined_at'] as String),
          entriesCount: (r['entries_count'] as num).toInt(),
          gavePaisa: (r['gave_paisa'] as num).toInt(),
          gotPaisa: (r['got_paisa'] as num).toInt(),
          lastEntryAt: r['last_entry_at'] == null
              ? null
              : DateTime.parse(r['last_entry_at'] as String),
        ),
    ];
  }

  @override
  Future<List<ActivityItem>> activity(String spaceId, {int limit = 100}) async {
    final rows = await _c
        .from('activity_feed')
        .select()
        .eq('space_id', spaceId)
        .order('at', ascending: false)
        .limit(limit);
    return [
      for (final r in rows)
        ActivityItem(
          at: DateTime.parse(r['at'] as String),
          kind: switch (r['kind'] as String) {
            'entry_added' => ActivityKind.entryAdded,
            'entry_cancelled' => ActivityKind.entryCancelled,
            _ => ActivityKind.memberJoined,
          },
          actorId: r['actor_id'] as String,
          actorName: r['actor_name'] as String?,
          partyName: r['party_name'] as String?,
          partyId: r['party_id'] as String?,
          amountPaisa: (r['amount_paisa'] as num?)?.toInt(),
          direction: r['direction'] as String?,
          entryId: r['entry_id'] as String?,
          note: r['note'] as String?,
        ),
    ];
  }

  @override
  Future<String> createInviteToken(String spaceId, MemberRole role) =>
      _c.rpc<String>(
        'create_invite',
        params: {'p_space': spaceId, 'p_role': role.name},
      );

  @override
  Future<InvitePreview?> previewInvite(String token) async {
    final rows = await _c.rpc<List<dynamic>>(
      'invite_preview',
      params: {'p_token': token},
    );
    if (rows.isEmpty) return null;
    final r = rows.first as Map<String, dynamic>;
    return InvitePreview(
      spaceName: r['space_name'] as String,
      inviterName: r['inviter_name'] as String?,
      role: MemberRole.values.byName(r['role'] as String),
      valid: r['valid'] as bool,
    );
  }

  @override
  Future<String> acceptInvite(String token) =>
      _c.rpc<String>('accept_invite', params: {'p_token': token});

  @override
  Future<void> changeRole(String spaceId, String userId, MemberRole role) => _c
      .from('space_members')
      .update({'role': role.name})
      .eq('space_id', spaceId)
      .eq('user_id', userId);

  @override
  Future<void> removeMember(String spaceId, String userId) => _c
      .from('space_members')
      .delete()
      .eq('space_id', spaceId)
      .eq('user_id', userId);

  @override
  Future<void> leave(String spaceId) =>
      _c.rpc<void>('leave_space', params: {'p_space': spaceId});

  @override
  Future<DateTime?> lockedUntil(String spaceId) async {
    final r = await _c
        .from('books')
        .select('locked_until')
        .eq('space_id', spaceId)
        .eq('is_default', true)
        .single();
    return r['locked_until'] == null
        ? null
        : DateTime.parse(r['locked_until'] as String);
  }

  @override
  Future<void> setLock(String spaceId, DateTime? until) async {
    final d = until == null
        ? null
        : '${until.year.toString().padLeft(4, '0')}-${until.month.toString().padLeft(2, '0')}-${until.day.toString().padLeft(2, '0')}';
    await _c
        .from('books')
        .update({'locked_until': d})
        .eq('space_id', spaceId)
        .eq('is_default', true);
  }
}

class PreviewGroupsRepository implements GroupsRepository {
  PreviewGroupsRepository(this._ledger);
  final LedgerRepository _ledger;
  final _members = <String, List<Member>>{
    'p': [
      Member(
        userId: 'preview',
        name: 'You',
        role: MemberRole.owner,
        joinedAt: DateTime(2026, 1, 1),
      ),
    ],
    'f': [
      Member(
        userId: 'preview',
        name: 'You',
        role: MemberRole.owner,
        joinedAt: DateTime(2026, 1, 1),
        entriesCount: 3,
        gavePaisa: 1350000,
        gotPaisa: 2500000,
      ),
      Member(
        userId: 'u2',
        name: 'Ammi',
        role: MemberRole.manager,
        joinedAt: DateTime(2026, 1, 3),
        entriesCount: 5,
        gavePaisa: 800000,
        gotPaisa: 200000,
      ),
      Member(
        userId: 'u3',
        name: 'Bilal',
        role: MemberRole.member,
        joinedAt: DateTime(2026, 2, 10),
        entriesCount: 1,
        gavePaisa: 50000,
      ),
      Member(
        userId: 'u4',
        name: 'Sara',
        role: MemberRole.viewer,
        joinedAt: DateTime(2026, 3, 2),
      ),
    ],
    'b': [
      Member(
        userId: 'u5',
        name: 'Ahmed Mamu',
        role: MemberRole.owner,
        joinedAt: DateTime(2026, 1, 1),
        entriesCount: 12,
        gavePaisa: 9000000,
        gotPaisa: 5400000,
      ),
      Member(
        userId: 'preview',
        name: 'You',
        role: MemberRole.manager,
        joinedAt: DateTime(2026, 1, 2),
      ),
      Member(
        userId: 'u6',
        name: 'Saeed',
        role: MemberRole.member,
        joinedAt: DateTime(2026, 1, 5),
      ),
      Member(
        userId: 'u7',
        name: 'Bilal',
        role: MemberRole.member,
        joinedAt: DateTime(2026, 1, 5),
      ),
      Member(
        userId: 'u8',
        name: 'Munshi',
        role: MemberRole.viewer,
        joinedAt: DateTime(2026, 4, 1),
      ),
    ],
  };
  final _locks = <String, DateTime?>{};
  final _invites = <String, (String, MemberRole)>{};

  @override
  Future<List<Member>> members(String spaceId) async =>
      List.of(_members[spaceId] ?? const []);

  @override
  Future<List<ActivityItem>> activity(String spaceId, {int limit = 100}) async {
    final entries = await _ledger.entriesForSpace(spaceId);
    final parties = {
      for (final pb in await _ledger.partiesWithBalances(spaceId))
        pb.party.id: pb.party.name,
    };
    final items = <ActivityItem>[
      for (final e in entries)
        ActivityItem(
          at: e.createdAt,
          kind: e.isReversal
              ? ActivityKind.entryCancelled
              : ActivityKind.entryAdded,
          actorId: e.createdBy,
          actorName: e.createdByName,
          partyName: parties[e.partyId],
          partyId: e.partyId,
          amountPaisa: e.amountPaisa,
          direction: e.direction.name,
          entryId: e.id,
          note: e.note,
        ),
      for (final m in _members[spaceId] ?? const <Member>[])
        ActivityItem(
          at: m.joinedAt,
          kind: ActivityKind.memberJoined,
          actorId: m.userId,
          actorName: m.name,
        ),
    ];
    items.sort((a, b) => b.at.compareTo(a.at));
    return items.take(limit).toList();
  }

  @override
  Future<String> createInviteToken(String spaceId, MemberRole role) async {
    final token = List.generate(
      64,
      (i) => '0123456789abcdef'[(i * 7 + spaceId.hashCode) % 16],
    ).join();
    _invites[token] = (spaceId, role);
    return token;
  }

  @override
  Future<InvitePreview?> previewInvite(String token) async {
    final inv = _invites[token];
    if (inv == null) {
      // Any well formed code previews as a sample family invite in preview mode.
      return token.length == 64
          ? const InvitePreview(
              spaceName: 'Khan Family',
              inviterName: 'Ali Khan',
              role: MemberRole.member,
              valid: true,
            )
          : null;
    }
    return InvitePreview(
      spaceName: inv.$1,
      inviterName: 'You',
      role: inv.$2,
      valid: true,
    );
  }

  @override
  Future<String> acceptInvite(String token) async => 'f';

  @override
  Future<void> changeRole(
    String spaceId,
    String userId,
    MemberRole role,
  ) async {
    final list = _members[spaceId]!;
    final i = list.indexWhere((m) => m.userId == userId);
    final m = list[i];
    list[i] = Member(
      userId: m.userId,
      name: m.name,
      role: role,
      joinedAt: m.joinedAt,
      entriesCount: m.entriesCount,
      gavePaisa: m.gavePaisa,
      gotPaisa: m.gotPaisa,
    );
  }

  @override
  Future<void> removeMember(String spaceId, String userId) async =>
      _members[spaceId]!.removeWhere((m) => m.userId == userId);

  @override
  Future<void> leave(String spaceId) async => removeMember(spaceId, 'preview');

  @override
  Future<DateTime?> lockedUntil(String spaceId) async => _locks[spaceId];

  @override
  Future<void> setLock(String spaceId, DateTime? until) async =>
      _locks[spaceId] = until;
}

final groupsRepositoryProvider = Provider<GroupsRepository>((ref) {
  if (AppConfig.isConfigured) {
    return SupabaseGroupsRepository(sb.Supabase.instance.client);
  }
  return PreviewGroupsRepository(ref.watch(ledgerRepositoryProvider));
});

final groupsVersionProvider = NotifierProvider<GroupsVersion, int>(
  GroupsVersion.new,
);

class GroupsVersion extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final membersProvider = FutureProvider.family<List<Member>, String>((
  ref,
  spaceId,
) {
  ref.watch(groupsVersionProvider);
  ref.watch(ledgerVersionProvider(spaceId));
  return ref.watch(groupsRepositoryProvider).members(spaceId);
});

final activityProvider = FutureProvider.family<List<ActivityItem>, String>((
  ref,
  spaceId,
) {
  ref.watch(groupsVersionProvider);
  ref.watch(ledgerVersionProvider(spaceId));
  return ref.watch(groupsRepositoryProvider).activity(spaceId);
});

final lockedUntilProvider = FutureProvider.family<DateTime?, String>((
  ref,
  spaceId,
) {
  ref.watch(groupsVersionProvider);
  return ref.watch(groupsRepositoryProvider).lockedUntil(spaceId);
});
