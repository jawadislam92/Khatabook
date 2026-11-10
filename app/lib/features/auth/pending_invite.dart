import 'package:flutter_riverpod/flutter_riverpod.dart';

/// An invite token waiting for the person to finish signing in. Set when an
/// invite link opens the app, or when someone pastes a link on the sign in
/// screen. Once signed in, the router opens the join screen for it.
final pendingInviteProvider = NotifierProvider<PendingInvite, String?>(
  PendingInvite.new,
);

class PendingInvite extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String token) => state = token;
  void clear() => state = null;
}
