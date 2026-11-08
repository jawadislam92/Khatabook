import 'package:flutter/material.dart';

/// Design tokens. Every colour in the app comes from here.
///
/// The palette is deliberately lively: a teal brand colour, a warm saffron
/// accent, and a distinct hue per kind of space, so screens feel different
/// from each other instead of one flat green. Text contrast still meets the
/// large text standard, and simple mode pushes it higher.
class Tokens {
  const Tokens._();

  // Brand
  static const primary = Color(0xFF0E8C7F); // teal
  static const primaryDeep = Color(0xFF0B6B61);
  static const primaryBright = Color(0xFF2DD4BF);
  static const saffron = Color(0xFFF59E0B);
  static const saffronDeep = Color(0xFFD97706);
  static const indigo = Color(0xFF4F46E5);
  static const indigoDeep = Color(0xFF3730A3);
  static const violet = Color(0xFF7C3AED);
  static const rose = Color(0xFFE11D48);
  static const sky = Color(0xFF0EA5E9);

  // Money semantics. Used together with an icon and words, never alone.
  static const get = Color(0xFF15803D);
  static const getDark = Color(0xFF4ADE80);
  static const getTint = Color(0xFFDCFCE7);
  static const give = Color(0xFFDC2626);
  static const giveDark = Color(0xFFF87171);
  static const giveTint = Color(0xFFFEE2E2);

  // Hue per space kind
  static const personalHue = indigo;
  static const familyHue = saffronDeep;
  static const businessHue = primary;

  // Neutrals with a cool bias so the warm accents pop
  static const paper = Color(0xFFFFFFFF);
  static const background = Color(0xFFF2F5F9);
  static const text = Color(0xFF15202B);
  static const muted = Color(0xFF55606E);
  static const rule = Color(0xFFDDE3EA);

  static const backgroundDark = Color(0xFF0F1620);
  static const paperDark = Color(0xFF1A2330);
  static const textDark = Color(0xFFEAEFF5);
  static const mutedDark = Color(0xFFA3AFBE);
  static const ruleDark = Color(0xFF2C3645);

  // Gradients used on headers and hero cards
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0E8C7F), Color(0xFF1D4ED8)],
  );
  static const sunsetGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF59E0B), Color(0xFFE11D48)],
  );
  static const violetGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
  );

  // Spacing scale
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 24.0;
  static const s6 = 32.0;
  static const s7 = 48.0;

  static const radius = 16.0;
  static const radiusLarge = 24.0;

  /// Minimum tap target heights.
  static const targetStandard = 48.0;
  static const targetSimple = 56.0;

  /// Text scale applied in simple mode on top of the system setting.
  static const simpleTextScale = 1.3;
}
