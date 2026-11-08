import '../../l10n/app_localizations.dart';
import '../spaces/spaces_repository.dart';

String roleLabel(AppLocalizations l, MemberRole r) => switch (r) {
  MemberRole.owner => l.roleOwner,
  MemberRole.manager => l.roleManager,
  MemberRole.member => l.roleMember,
  MemberRole.viewer => l.roleViewer,
};

String roleHint(AppLocalizations l, MemberRole r) => switch (r) {
  MemberRole.owner => l.roleOwnerHint,
  MemberRole.manager => l.roleManagerHint,
  MemberRole.member => l.roleMemberHint,
  MemberRole.viewer => l.roleViewerHint,
};

bool roleAtLeast(MemberRole have, MemberRole need) => have.index <= need.index;
