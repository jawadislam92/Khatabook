import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A large tappable card used for either/or choices (language, display mode).
/// Each option carries its own colour so the choice reads at a glance.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.titleStyle,
    this.color,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final TextStyle? titleStyle;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hue = color ?? scheme.primary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Tokens.radius),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: hue.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.3 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Material(
          color: selected
              ? hue.withValues(alpha: dark ? 0.28 : 0.12)
              : scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radius),
            side: BorderSide(
              color: selected ? hue : scheme.outline,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Tokens.radius),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Tokens.s4),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: hue,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, size: 30, color: Colors.white),
                    ),
                    const SizedBox(width: Tokens.s4),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style:
                              titleStyle ??
                              text.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: Tokens.s1),
                          Text(
                            subtitle!,
                            style: text.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: Tokens.s2),
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? hue : scheme.outline,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
