import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duebook/core/settings/app_settings.dart';
import 'package:duebook/features/onboarding/onboarding_screen.dart';

import 'helpers/pump_app.dart';

void main() {
  testWidgets('choosing Urdu switches the UI language immediately', (
    tester,
  ) async {
    final c = await pumpScreen(tester, const OnboardingScreen());
    expect(find.text('Choose your language'), findsOneWidget);
    await tester.tap(find.text('اردو'));
    await tester.pumpAndSettle();
    expect(c.read(appSettingsProvider).languageCode, 'ur');
    expect(find.text('اپنی زبان چنیں'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(OnboardingScreen))),
      TextDirection.rtl,
    );
  });

  testWidgets(
    'Big and Simple choice turns simple mode on and finishes onboarding',
    (tester) async {
      final c = await pumpScreen(tester, const OnboardingScreen());
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Who will use this phone?'), findsOneWidget);
      await tester.tap(find.text('Big and Simple'));
      await tester.pumpAndSettle();
      expect(c.read(appSettingsProvider).simpleMode, isTrue);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(c.read(appSettingsProvider).onboardingDone, isTrue);
    },
  );

  testWidgets('back from step two returns to language step', (tester) async {
    await pumpScreen(tester, const OnboardingScreen());
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your language'), findsOneWidget);
  });
}
