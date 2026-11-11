// Buttons at the bottom of slide-up panels must sit above the phone's own
// navigation bar, so a tap reaches the app and not the phone.
import 'package:duebook/core/widgets/clear_of_system_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a panel button stays above the navigation bar', (tester) async {
    // A phone 2340 px tall at 3x, with a 48 dp navigation bar at the bottom.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(bottom: 144);
    tester.view.viewPadding = const FakeViewPadding(bottom: 144);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => ClearOfSystemBars(child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Panel'),
                      FilledButton(onPressed: () {}, child: const Text('Save')),
                    ],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final button = tester.getRect(find.text('Save'));
    const screenHeight = 2340 / 3;
    const navBar = 144 / 3;
    expect(
      button.bottom,
      lessThanOrEqualTo(screenHeight - navBar),
      reason: 'the Save button must not sit under the navigation bar',
    );
  });
}
