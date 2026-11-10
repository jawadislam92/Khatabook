import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the Material theme for a mode (standard or simple) and brightness.
class AppTheme {
  const AppTheme._();

  static const urduFont = 'NotoNastaliqUrdu';
  static const latinFallback = ['Roboto', 'sans-serif'];

  static ThemeData build({
    required Brightness brightness,
    required bool simpleMode,
    required Locale locale,
  }) {
    final dark = brightness == Brightness.dark;
    final isUrdu = locale.languageCode == 'ur';

    final scheme = ColorScheme(
      brightness: brightness,
      primary: dark ? Tokens.primaryBright : Tokens.primary,
      onPrimary: dark ? Tokens.backgroundDark : Colors.white,
      secondary: Tokens.saffronDeep,
      onSecondary: Colors.white,
      tertiary: Tokens.indigo,
      onTertiary: Colors.white,
      error: dark ? Tokens.giveDark : Tokens.give,
      onError: Colors.white,
      surface: dark ? Tokens.paperDark : Tokens.paper,
      onSurface: dark
          ? (simpleMode ? Colors.white : Tokens.textDark)
          : (simpleMode ? Colors.black : Tokens.text),
      surfaceContainerHighest: dark ? Tokens.ruleDark : Tokens.rule,
      onSurfaceVariant: dark ? Tokens.mutedDark : Tokens.muted,
      outline: dark ? Tokens.ruleDark : Tokens.rule,
    );

    final target = simpleMode ? Tokens.targetSimple : Tokens.targetStandard;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: isUrdu ? urduFont : null,
      // Latin names inside Urdu text (people, businesses) use the sans face.
      fontFamilyFallback: isUrdu ? latinFallback : null,
      scaffoldBackgroundColor: dark ? Tokens.backgroundDark : Tokens.background,
      // Fixed density so the 56 dp targets in simple mode stay 56 dp on
      // every platform instead of shrinking under adaptive density.
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );

    // Nastaliq needs more line height than Latin faces to avoid clipping.
    final textTheme = isUrdu
        ? base.textTheme
              .apply(fontFamily: urduFont, fontFamilyFallback: latinFallback)
              .copyWith(
                bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.9),
                bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.9),
                titleLarge: base.textTheme.titleLarge?.copyWith(height: 1.7),
              )
        : base.textTheme;

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Tokens.radius),
    );
    final buttonText = TextStyle(
      fontSize: simpleMode ? 20 : 17,
      fontWeight: FontWeight.w600,
      fontFamily: isUrdu ? urduFont : null,
      // Latin names inside Urdu text (people, businesses) use the sans face.
      fontFamilyFallback: isUrdu ? latinFallback : null,
      height: isUrdu ? 1.8 : null,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: base.scaffoldBackgroundColor,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(double.infinity, target),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(double.infinity, target),
          shape: buttonShape,
          textStyle: buttonText,
          side: BorderSide(color: scheme.primary, width: simpleMode ? 2 : 1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: Size(target, target),
          textStyle: buttonText.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radius),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: Tokens.s4,
          vertical: simpleMode ? Tokens.s5 : Tokens.s4,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radius),
          side: BorderSide(color: scheme.outline),
        ),
        margin: EdgeInsets.zero,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Tokens.saffron,
        foregroundColor: Tokens.text,
        extendedTextStyle: buttonText.copyWith(color: Tokens.text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radius),
        ),
      ),
      // The off state must still look like a switch: a dark knob with a
      // cross on a light track with a clear border. On is a white knob with
      // a tick on the main colour.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white
              : (dark ? Tokens.mutedDark : Tokens.muted),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.primary
              : (dark ? Tokens.paperDark : Tokens.paper),
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.primary
              : (dark ? Tokens.mutedDark : Tokens.muted),
        ),
        trackOutlineWidth: const WidgetStatePropertyAll(2),
        thumbIcon: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Icon(Icons.check_rounded, color: scheme.primary)
              : Icon(
                  Icons.close_rounded,
                  color: dark ? Tokens.paperDark : Tokens.paper,
                ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: simpleMode ? Tokens.s4 : Tokens.s3,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(color: scheme.outline),
    );
  }
}
