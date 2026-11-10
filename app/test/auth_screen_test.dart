import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duebook/features/auth/auth_screen.dart';

import 'helpers/pump_app.dart';

void main() {
  test('password rule: any 6 characters or more', () {
    expect(AuthScreenState.passwordIsStrong('123456'), isTrue);
    expect(AuthScreenState.passwordIsStrong('abcdef'), isTrue);
    expect(AuthScreenState.passwordIsStrong('ali786'), isTrue);
    expect(AuthScreenState.passwordIsStrong('12345'), isFalse);
    expect(AuthScreenState.passwordIsStrong(''), isFalse);
  });

  testWidgets('shows preview banner and validates email', (tester) async {
    await pumpScreen(tester, const AuthScreen());
    expect(
      find.text('Preview build. Nothing is saved to a server.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'not-an-email',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'x');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(
      find.text('That email address does not look right.'),
      findsOneWidget,
    );
  });

  testWidgets('switches to create account and back', (tester) async {
    await pumpScreen(tester, const AuthScreen());
    await tester.ensureVisible(find.text('New here? Create an account'));
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Your name'), findsOneWidget);
    await tester.ensureVisible(find.text('Already have an account? Sign in'));
    await tester.tap(find.text('Already have an account? Sign in'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Your name'), findsNothing);
  });
}
