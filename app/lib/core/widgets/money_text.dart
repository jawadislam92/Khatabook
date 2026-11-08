import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../utils/money.dart';
import '../utils/number_words.dart';

/// Rupee amount with the get/give colour, an arrow, and in simple mode the
/// amount in words underneath. Colour is never the only signal.
class MoneyText extends StatelessWidget {
  const MoneyText({
    super.key,
    required this.paisa,
    this.sign,
    this.size = 20,
    this.words = false,
    this.align = TextAlign.start,
  });

  final int paisa;

  /// Force the colour: true for get, false for give, null for neutral.
  final bool? sign;
  final double size;
  final bool words;
  final TextAlign align;

  static Color colorFor(BuildContext context, bool? sign) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (sign == null) return Theme.of(context).colorScheme.onSurface;
    return sign
        ? (dark ? Tokens.getDark : Tokens.get)
        : (dark ? Tokens.giveDark : Tokens.give);
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(context, sign);
    final lang = Localizations.localeOf(context).languageCode;
    return Column(
      crossAxisAlignment: align == TextAlign.center
          ? CrossAxisAlignment.center
          : (align == TextAlign.end
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Rs ${Money.format(paisa.abs())}',
          textAlign: align,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            color: color,
            fontFamily: 'Roboto',
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (words && paisa.abs() >= 100)
          Text(
            NumberWords.rupees(paisa.abs() ~/ 100, lang),
            textAlign: align,
            style: TextStyle(
              fontSize: size * 0.6,
              color: color.withValues(alpha: 0.85),
            ),
          ),
      ],
    );
  }
}
