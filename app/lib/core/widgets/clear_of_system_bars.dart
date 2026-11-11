import 'package:flutter/material.dart';

/// Keeps every screen, panel and dialog above the phone's own navigation
/// bar (the back, home and recent buttons, or the gesture line).
///
/// Newer Android versions let apps draw behind that bar. Buttons placed at
/// the bottom of a slide-up panel then sat under it, and taps went to the
/// phone instead of the app. Wrapping the whole app once fixes every screen,
/// including ones added later. The strip behind the bar takes the page
/// background colour, so it looks like part of the app.
class ClearOfSystemBars extends StatelessWidget {
  const ClearOfSystemBars({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: SafeArea(top: false, left: false, right: false, child: child),
  );
}
