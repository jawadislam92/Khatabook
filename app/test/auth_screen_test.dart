import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duebook/features/auth/auth_screen.dart';

import 'helpers/pump_app.dart';

void main() {
  test('password rule: 10 chars with upper, lower and digit', () {
    expect(AuthScreenState.passwordIsStrong('Password12'), isTrue);
    expect(AuthScreenState.passwordIsStrong('password12'), isFalse);
    expect(AuthScreenState.passwordIsStrong('PASSWORD12'), isFalse);
    expect(AuthScreenState.passwordIsStrong('Passwordxx'), isFalse);
    expect(AuthScreenState.passwordIsStrong('Pass12'), isFalse);
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
