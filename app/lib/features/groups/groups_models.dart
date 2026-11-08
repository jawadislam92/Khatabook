import '../spaces/spaces_repository.dart';

class Member {
  const Member({
    required this.userId,
    required this.name,
    required this.role,
    required this.joinedAt,
    this.entriesCount = 0,
    this.gavePaisa = 0,
    this.gotPaisa = 0,
    this.lastEntryAt,
  });
  final String userId;
  final String name;
  final MemberRole role;
  final DateTime joinedAt;
  final int entriesCount;
  final int gavePaisa;
  final int gotPaisa;
  final DateTime? lastEntryAt;
}

enum ActivityKind { entryAdded, entryCancelled, memberJoined }

class ActivityItem {
  const ActivityItem({
    required this.at,
    required this.kind,
    required this.actorId,
    this.actorName,
    this.partyName,
    this.partyId,
    this.amountPaisa,
    this.direction,
    this.entryId,
    this.note,
  });
  final DateTime at;
  final ActivityKind kind;
  final String actorId;
  final String? actorName;
  final String? partyName;
  final String? partyId;
  final int? amountPaisa;
  final String? direction;
  final String? entryId;
  final String? note;
}

class InvitePreview {
  const InvitePreview({
    required this.spaceName,
    required this.inviterName,
    required this.role,
    required this.valid,
  });
  final String spaceName;
  final String? inviterName;
  final MemberRole role;
  final bool valid;
}

/// The shareable link carries the token. The page does not exist yet; the
/// app opens the link directly through its intent filter, and the join
/// screen also accepts the pasted link or the bare code.
class InviteLink {
  const InviteLink._();
  static const host = 'duebook.sparkingasia.com';
  static String build(String token) => 'https://$host/join/$token';

  /// Extracts the token from a full link, a custom scheme link, or a bare code.
  static String? parse(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'([0-9a-f]{64})').firstMatch(s);
    return m?.group(1);
  }
}
