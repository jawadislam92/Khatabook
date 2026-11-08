import 'package:flutter/material.dart';

/// Shows how many PIN digits are typed without showing the digits.
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.filled,
    this.max = 6,
    this.error = false,
  });

  final int filled;
  final int max;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = error ? scheme.error : scheme.primary;
    return Semantics(
      label: '$filled digits entered',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < max; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.symmetric(horizontal: 7),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? color : Colors.transparent,
                border: Border.all(
                  color: i < filled ? color : scheme.outline,
                  width: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
