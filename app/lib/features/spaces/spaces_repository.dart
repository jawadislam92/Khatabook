import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/config/app_config.dart';

enum SpaceKind { personal, group }

enum MemberRole { owner, manager, member, viewer }

class Space {
  const Space({
    required this.id,
    required this.name,
    required this.kind,
    required this.businessEnabled,
    required this.myRole,
    required this.memberCount,
  });

  final String id;
  final String name;
  final SpaceKind kind;
  final bool businessEnabled;
  final MemberRole myRole;
  final int memberCount;
}

abstract class SpacesRepository {
  Future<List<Space>> listMine();
  Future<Space> createGroup(String name, {bool business = false});
}

class SupabaseSpacesRepository implements SpacesRepository {
  SupabaseSpacesRepository(this._client);
  final sb.SupabaseClient _client;

  @override
  Future<List<Space>> listMine() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from('spaces')
        .select(
          'id, name, kind, business_enabled, deleted_at, space_members(user_id, role)',
        )
        .isFilter('deleted_at', null)
        .order('kind')
        .order('created_at');
    return [
      for (final r in rows)
        () {
          final members = (r['space_members'] as List)
              .cast<Map<String, dynamic>>();
          final mine = members.firstWhere(
            (m) => m['user_id'] == uid,
            orElse: () => {'role': 'viewer'},
          );
          return Space(
            id: r['id'] as String,
            name: r['name'] as String,
            kind: r['kind'] == 'personal'
                ? SpaceKind.personal
                : SpaceKind.group,
            businessEnabled: r['business_enabled'] as bool,
            myRole: MemberRole.values.byName(mine['role'] as String),
            memberCount: members.length,
          );
        }(),
    ];
  }

  @override
  Future<Space> createGroup(String name, {bool business = false}) async {
    final id = await _client.rpc<String>(
      'create_space',
      params: {'p_name': name.trim(), 'p_business_enabled': business},
    );
    return Space(
      id: id,
      name: name.trim(),
      kind: SpaceKind.group,
      businessEnabled: business,
      myRole: MemberRole.owner,
      memberCount: 1,
    );
  }
}

class PreviewSpacesRepository implements SpacesRepository {
  final _spaces = <Space>[
    const Space(
      id: 'p',
      name: 'Personal',
      kind: SpaceKind.personal,
      businessEnabled: false,
      myRole: MemberRole.owner,
      memberCount: 1,
    ),
    const Space(
      id: 'f',
      name: 'Family',
      kind: SpaceKind.group,
      businessEnabled: false,
      myRole: MemberRole.owner,
      memberCount: 4,
    ),
    const Space(
      id: 'b',
      name: 'Ahmed CCTV & Solar',
      kind: SpaceKind.group,
      businessEnabled: true,
      myRole: MemberRole.manager,
      memberCount: 5,
    ),
  ];

  @override
  Future<List<Space>> listMine() async => List.unmodifiable(_spaces);

  @override
  Future<Space> createGroup(String name, {bool business = false}) async {
    final s = Space(
      id: 'g${_spaces.length}',
      name: name.trim(),
      kind: SpaceKind.group,
      businessEnabled: business,
      myRole: MemberRole.owner,
      memberCount: 1,
    );
    _spaces.add(s);
    return s;
  }
}

final spacesRepositoryProvider = Provider<SpacesRepository>((ref) {
  if (AppConfig.isConfigured) {
    return SupabaseSpacesRepository(sb.Supabase.instance.client);
  }
  return PreviewSpacesRepository();
});

final mySpacesProvider = FutureProvider<List<Space>>((ref) {
  return ref.watch(spacesRepositoryProvider).listMine();
});
