import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_repository.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/ledger/add_entry_screen.dart';
import '../../features/ledger/entry_detail_screen.dart';
import '../../features/ledger/ledger_models.dart';
import '../../features/ledger/party_screen.dart';
import '../../features/ledger/space_home_screen.dart';
import '../../features/lock/lock_screen.dart';
import '../../features/lock/set_pin_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/spaces/spaces_screen.dart';
import '../security/app_lock.dart';
import '../settings/app_settings.dart';

/// Order of gates, top to bottom: onboarding, sign in, PIN set up, lock.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _Refresh();
  ref.listen(appSettingsProvider, (_, _) => refresh.ping());
  ref.listen(currentUserProvider, (_, _) => refresh.ping());
  ref.listen(appLockProvider, (_, _) => refresh.ping());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/spaces',
    refreshListenable: refresh,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      final settings = ref.read(appSettingsProvider);
      final user = ref.read(currentUserProvider);
      final lock = ref.read(appLockProvider);
      final here = state.matchedLocation;

      if (!settings.onboardingDone) {
        return here == '/onboarding' ? null : '/onboarding';
      }
      if (user.isLoading) return null;
      if (user.value == null) return here == '/auth' ? null : '/auth';
      if (!lock.pinSet) return here == '/set-pin' ? null : '/set-pin';
      if (lock.locked) return here == '/lock' ? null : '/lock';
      if (const {'/onboarding', '/auth', '/set-pin', '/lock'}.contains(here)) {
        return '/spaces';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
      GoRoute(path: '/set-pin', builder: (_, _) => const SetPinScreen()),
      GoRoute(path: '/lock', builder: (_, _) => const LockScreen()),
      GoRoute(path: '/spaces', builder: (_, _) => const SpacesScreen()),
      GoRoute(
        path: '/space/:sid',
        builder: (_, st) => SpaceHomeScreen(spaceId: st.pathParameters['sid']!),
        routes: [
          GoRoute(
            path: 'add',
            builder: (_, st) => AddEntryScreen(
              spaceId: st.pathParameters['sid']!,
              direction: st.uri.queryParameters['direction'] == 'got'
                  ? EntryDirection.got
                  : EntryDirection.gave,
              partyId: st.uri.queryParameters['party'],
            ),
          ),
          GoRoute(
            path: 'party/:pid',
            builder: (_, st) => PartyScreen(
              spaceId: st.pathParameters['sid']!,
              partyId: st.pathParameters['pid']!,
            ),
            routes: [
              GoRoute(
                path: 'entry/:eid',
                builder: (_, st) => EntryDetailScreen(
                  spaceId: st.pathParameters['sid']!,
                  partyId: st.pathParameters['pid']!,
                  entryId: st.pathParameters['eid']!,
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/change-pin',
        builder: (context, _) => SetPinScreen(onDone: () => context.pop()),
      ),
    ],
  );
});

class _Refresh extends ChangeNotifier {
  void ping() => notifyListeners();
}
