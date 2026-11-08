import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Standard page: title, always visible back button when there is somewhere
/// to go back to, comfortable padding, scrolls when content is tall.
class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.bottom,
    this.floatingActionButton,
    this.scroll = true,
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final Widget? bottom;
  final Widget? floatingActionButton;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.s4,
        Tokens.s2,
        Tokens.s4,
        Tokens.s5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: scroll ? SingleChildScrollView(child: body) : body),
            if (bottom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Tokens.s4,
                  0,
                  Tokens.s4,
                  Tokens.s4,
                ),
                child: bottom,
              ),
          ],
        ),
      ),
    );
  }
}
