import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khatabook/core/theme/app_theme.dart';
import 'package:khatabook/core/theme/tokens.dart';
import 'package:khatabook/core/widgets/big_button.dart';

import 'helpers/pump_app.dart';

void main() {
  testWidgets('standard mode buttons are at least 48 dp tall', (tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: BigButton(label: 'Save', onPressed: () {}),
      ),
    );
    final size = tester.getSize(find.byType(FilledButton));
    expect(size.height, greaterThanOrEqualTo(Tokens.targetStandard));
  });

  testWidgets('simple mode buttons are at least 56 dp tall', (tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: BigButton(label: 'Save', onPressed: () {}),
      ),
      simpleMode: true,
    );
    final size = tester.getSize(find.byType(FilledButton));
    expect(size.height, greaterThanOrEqualTo(Tokens.targetSimple));
  });

  test('simple mode uses full black text on light for contrast', () {
    final t = AppTheme.build(
      brightness: Brightness.light,
      simpleMode: true,
      locale: const Locale('en'),
    );
    expect(t.colorScheme.onSurface, Colors.black);
    final s = AppTheme.build(
      brightness: Brightness.light,
      simpleMode: false,
      locale: const Locale('en'),
    );
    expect(s.colorScheme.onSurface, isNot(Colors.black));
  });

  test('Urdu locale switches to the Nastaliq face with taller lines', () {
    final t = AppTheme.build(
      brightness: Brightness.light,
      simpleMode: false,
      locale: const Locale('ur'),
    );
    expect(t.textTheme.bodyLarge?.fontFamily, AppTheme.urduFont);
    expect(t.textTheme.bodyLarge?.height, greaterThan(1.5));
  });
}
