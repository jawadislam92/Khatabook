import 'package:flutter/material.dart';

/// Design tokens. Every colour in the app comes from here.
class Tokens {
  const Tokens._();

  // Brand
  static const primary = Color(0xFF1D7A4A); // deep ledger green
  static const primaryDark = Color(0xFF5FC48C);
  static const ink = Color(0xFF213A5C);

  // Money semantics. Used together with an icon and words, never alone.
  static const get = Color(0xFF1D7A4A);
  static const getDark = Color(0xFF5FC48C);
  static const give = Color(0xFFB03A2E);
  static const giveDark = Color(0xFFF08B7E);

  // Neutrals with a slight warm bias
  static const paper = Color(0xFFFFFDF8);
  static const background = Color(0xFFF5F4EF);
  static const text = Color(0xFF1D2430);
  static const muted = Color(0xFF5B6473);
  static const rule = Color(0xFFD9D6CC);

  static const backgroundDark = Color(0xFF151A22);
  static const paperDark = Color(0xFF1D232D);
  static const textDark = Color(0xFFE8E9E6);
  static const mutedDark = Color(0xFFA2AAB6);
  static const ruleDark = Color(0xFF343C49);

  // Spacing scale
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 24.0;
  static const s6 = 32.0;
  static const s7 = 48.0;

  static const radius = 12.0;

  /// Minimum tap target heights.
  static const targetStandard = 48.0;
  static const targetSimple = 56.0;

  /// Text scale applied in simple mode on top of the system setting.
  static const simpleTextScale = 1.3;
}
