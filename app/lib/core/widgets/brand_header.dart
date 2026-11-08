import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Gradient band with the app mark, used at the top of sign in and lock.
class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.gradient = Tokens.heroGradient,
    this.icon = Icons.menu_book_rounded,
  });

  final String title;
  final String? subtitle;
  final Gradient gradient;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        Tokens.s5,
        Tokens.s6,
        Tokens.s5,
        Tokens.s6,
      ),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(Tokens.radiusLarge + 8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            ),
            child: Icon(icon, color: Colors.white, size: 36),
          ),
          const SizedBox(height: Tokens.s4),
          Text(
            title,
            style: text.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: Tokens.s1),
            Text(
              subtitle!,
              style: text.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
