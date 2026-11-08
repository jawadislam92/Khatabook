import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Large on screen digit keypad for PINs and amounts.
class NumberPad extends StatelessWidget {
  const NumberPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.trailing,
  });

  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;

  /// Optional widget in the bottom left slot, for example a fingerprint button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String d) => _PadKey(
      label: d,
      onTap: () {
        HapticFeedback.selectionClick();
        onDigit(d);
      },
    );
    return LayoutBuilder(
      builder: (context, c) {
        final size = (c.maxWidth / 3).clamp(64.0, 96.0);
        return SizedBox(
          width: size * 3,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.35,
            children: [
              for (var i = 1; i <= 9; i++) key('$i'),
              trailing ?? const SizedBox.shrink(),
              key('0'),
              Semantics(
                button: true,
                label: MaterialLocalizations.of(context).deleteButtonTooltip,
                child: InkResponse(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onBackspace();
                  },
                  radius: 40,
                  child: Icon(
                    Icons.backspace_outlined,
                    size: 30,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(Tokens.s1),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radius),
          side: BorderSide(color: scheme.outline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Tokens.radius),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
