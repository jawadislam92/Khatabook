// The easy ways in: join from an invite with just a name, Google without
// a scary error when the picker is closed, and keeping a name-only login safe.
import 'package:duebook/features/auth/auth_repository.dart';
import 'package:duebook/features/auth/auth_screen.dart';
import 'package:duebook/features/auth/pending_invite.dart';
import 'package:duebook/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/pump_app.dart';

final _token = 'a' * 64;

class _ClosedPicker extends PreviewAuthRepository {
  @override
  Future<void> signInWithGoogle() async =>
      throw const AuthFailure(AuthFailureKind.cancelled);
}

class _Waiting extends PendingInvite {
  @override
  String? build() => _token;
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('invite link plus a name signs in with no email or password', (
    tester,
  ) async {
    _phoneSize(tester);
    final repo = PreviewAuthRepository();
    final container = await pumpScreen(
      tester,
      const AuthScreen(),
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
    );
    expect(find.text('Were you sent an invite link?'), findsOneWidget);
    expect(find.text('Join with my name'), findsNothing, reason: 'closed');
    await tester.tap(find.text('Were you sent an invite link?'));
    await tester.pumpAndSettle();

    // A name without a link is refused.
    await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Nani');
    await tester.tap(find.text('Join with my name'));
    await tester.pumpAndSettle();
    expect(repo.currentUser, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Invite link'),
      'Join our book: https://duebook.sparkingasia.com/join/$_token',
    );
    await tester.tap(find.text('Join with my name'));
    await tester.pumpAndSettle();
    expect(repo.currentUser?.displayName, 'Nani');
    expect(repo.currentUser?.isGuest, isTrue);
    expect(container.read(pendingInviteProvider), _token);
  });

  testWidgets('opened from an invite link, the card is open and filled in', (
    tester,
  ) async {
    _phoneSize(tester);
    await pumpScreen(
      tester,
      const AuthScreen(),
      overrides: [pendingInviteProvider.overrideWith(_Waiting.new)],
    );
    expect(find.text('Join with my name'), findsOneWidget);
    expect(find.textContaining(_token), findsOneWidget);
  });

  testWidgets('closing the Google picker shows no error', (tester) async {
    _phoneSize(tester);
    await pumpScreen(
      tester,
      const AuthScreen(),
      overrides: [authRepositoryProvider.overrideWithValue(_ClosedPicker())],
    );
    await tester.ensureVisible(find.text('Continue with Google'));
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('a name-only login is asked to connect Google', (tester) async {
    _phoneSize(tester);
    final repo = PreviewAuthRepository();
    await tester.runAsync(() => repo.joinWithName('Nani', languageCode: 'en'));
    await pumpScreen(
      tester,
      const SettingsScreen(),
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpAndSettle();
    expect(find.text('Your login is only on this phone'), findsOneWidget);

    // Signing out warns that the login would be lost.
    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot get back in'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Connect Google'));
    await tester.tap(find.text('Connect Google'));
    await tester.pumpAndSettle();
    expect(find.text('Google is connected.'), findsOneWidget);
    expect(find.text('Your login is only on this phone'), findsNothing);
    expect(repo.currentUser?.isGuest, isFalse);
  });
}
