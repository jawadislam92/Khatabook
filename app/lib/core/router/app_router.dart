import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/contacts/import_contacts_screen.dart';
import '../../features/auth/auth_repository.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/auth/pending_invite.dart';
import '../../features/groups/activity_screen.dart';
import '../../features/groups/join_screen.dart';
import '../../features/groups/members_screen.dart';
import '../../features/invoices/bill_screen.dart';
import '../../features/invoices/business_profile_screen.dart';
import '../../features/invoices/finish_job_screen.dart';
import '../../features/invoices/invoice_screen.dart';
import '../../features/invoices/invoices_tab.dart';
import '../../features/jobs/business_home_screen.dart';
import '../../features/jobs/job_detail_screen.dart';
import '../../features/jobs/new_job_screen.dart';
import '../../features/jobs/notifications_screen.dart';
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
import '../config/app_config.dart';
import '../security/app_lock.dart';
import '../settings/app_settings.dart';

/// Order of gates, top to bottom: onboarding, sign in, PIN set up, lock.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _Refresh();
  ref.listen(appSettingsProvider, (_, _) => refresh.ping());
  ref.listen(currentUserProvider, (_, _) => refresh.ping());
  ref.listen(appLockProvider, (_, _) => refresh.ping());
  ref.listen(pendingInviteProvider, (_, _) => refresh.ping());
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
      // The local test login on this computer has no PIN to type.
      if (!ref.read(devAutoSignInProvider)) {
        if (!lock.pinSet) return here == '/set-pin' ? null : '/set-pin';
        if (lock.locked) return here == '/lock' ? null : '/lock';
      }
      // Signed in after opening an invite: show that invite now.
      final invite = ref.read(pendingInviteProvider);
      if (invite != null && here != '/join') return '/join?token=$invite';
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
            path: 'job/new',
            builder: (_, st) =>
                NewJobScreen(spaceId: st.pathParameters['sid']!),
          ),
          GoRoute(
            path: 'job/:jid',
            builder: (_, st) => JobDetailScreen(
              spaceId: st.pathParameters['sid']!,
              jobId: st.pathParameters['jid']!,
            ),
            routes: [
              GoRoute(
                path: 'finish',
                builder: (_, st) => FinishJobScreen(
                  spaceId: st.pathParameters['sid']!,
                  jobId: st.pathParameters['jid']!,
                ),
              ),
              GoRoute(
                path: 'bill',
                builder: (_, st) => BillScreen(
                  spaceId: st.pathParameters['sid']!,
                  jobId: st.pathParameters['jid']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'invoice/:iid',
            builder: (_, st) => InvoiceScreen(
              spaceId: st.pathParameters['sid']!,
              invoiceId: st.pathParameters['iid']!,
            ),
          ),
          GoRoute(
            path: 'import-contacts',
            builder: (_, st) =>
                ImportContactsScreen(spaceId: st.pathParameters['sid']!),
          ),
          GoRoute(
            path: 'members',
            builder: (_, st) =>
                MembersScreen(spaceId: st.pathParameters['sid']!),
          ),
          GoRoute(
            path: 'activity',
            builder: (_, st) =>
                ActivityScreen(spaceId: st.pathParameters['sid']!),
          ),
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
        path: '/join',
        builder: (_, st) => JoinScreen(token: st.uri.queryParameters['token']),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/business/:sid',
        builder: (_, st) => BusinessHomeScreen(
          spaceId: st.pathParameters['sid']!,
          initialTab: int.tryParse(st.uri.queryParameters['tab'] ?? '') ?? 0,
        ),
        routes: [
          GoRoute(
            path: 'profile',
            builder: (_, st) =>
                BusinessProfileScreen(spaceId: st.pathParameters['sid']!),
          ),
          GoRoute(
            path: 'items-report',
            builder: (_, st) =>
                ItemsReportScreen(spaceId: st.pathParameters['sid']!),
          ),
        ],
      ),
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
