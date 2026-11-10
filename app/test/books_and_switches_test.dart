// A new book is Family or Business, picked from two clear choices, and an
// off switch still looks like a switch.
import 'package:duebook/core/theme/app_theme.dart';
import 'package:duebook/features/spaces/spaces_repository.dart';
import 'package:duebook/features/spaces/spaces_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/pump_app.dart';

void main() {
  testWidgets('new book: Family is picked first, Business can be picked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = await pumpScreen(tester, const SpacesScreen());
    await tester.pumpAndSettle();
    expect(find.text('Personal'), findsNothing);

    await tester.tap(find.text('New book'));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNothing);
    expect(find.text('What is this book for?'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Bilal Shop');
    await tester.tap(find.text('Customers, jobs and bills.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final mine = await container.read(spacesRepositoryProvider).listMine();
    final made = mine.firstWhere((s) => s.name == 'Bilal Shop');
    expect(made.businessEnabled, isTrue);
    expect(mine.where((s) => s.kind == SpaceKind.personal), isEmpty);
  });

  test('an off switch has a dark knob, a border and a cross', () {
    for (final b in Brightness.values) {
      final t = AppTheme.build(
        brightness: b,
        simpleMode: false,
        locale: const Locale('en'),
      ).switchTheme;
      const off = <WidgetState>{};
      const on = {WidgetState.selected};
      final knob = t.thumbColor!.resolve(off)!;
      final track = t.trackColor!.resolve(off)!;
      expect(
        (knob.computeLuminance() - track.computeLuminance()).abs(),
        greaterThan(0.25),
        reason: 'knob must stand out from the track ($b)',
      );
      expect(t.trackOutlineColor!.resolve(off), knob);
      expect(t.thumbIcon!.resolve(off)!.icon, Icons.close_rounded);
      expect(t.thumbIcon!.resolve(on)!.icon, Icons.check_rounded);
    }
  });
}
