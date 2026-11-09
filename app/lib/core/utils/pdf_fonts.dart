import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Fonts for every PDF the app makes. Roboto for Latin and digits, Noto
/// Naskh Arabic for Urdu. The PDF engine shapes Arabic script one text run
/// at a time, so Urdu strings are given the Naskh face directly instead of
/// relying on glyph fallback, which would break the joins between letters.
class PdfFonts {
  const PdfFonts._(this.latin, this.latinBold, this.urdu, this.urduBold);
  final pw.Font latin, latinBold, urdu, urduBold;

  static Future<PdfFonts> load() async {
    Future<pw.Font> ttf(String name) async =>
        pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
    return PdfFonts._(
      await ttf('Roboto-Regular'),
      await ttf('Roboto-Bold'),
      await ttf('NotoNaskhArabic-Regular'),
      await ttf('NotoNaskhArabic-Bold'),
    );
  }

  static final _arabic = RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');
  static bool hasUrdu(String s) => _arabic.hasMatch(s);

  /// Document theme. Urdu documents read right to left and use Naskh as the
  /// base face so numbers and labels sit together naturally.
  pw.ThemeData theme({required bool rtl}) => rtl
      ? pw.ThemeData.withFont(
          base: urdu,
          bold: urduBold,
          fontFallback: [latin, latinBold],
        )
      : pw.ThemeData.withFont(
          base: latin,
          bold: latinBold,
          fontFallback: [urdu, urduBold],
        );

  pw.TextStyle styleFor(String s, pw.TextStyle? style) {
    final base = style ?? const pw.TextStyle();
    final bold = base.fontWeight == pw.FontWeight.bold;
    final ur = hasUrdu(s);
    return base.copyWith(
      font: ur ? (bold ? urduBold : urdu) : (bold ? latinBold : latin),
      fontNormal: ur ? urdu : latin,
      fontBold: ur ? urduBold : latinBold,
      fontItalic: ur ? urdu : latin,
      fontBoldItalic: ur ? urduBold : latinBold,
      fontFallback: ur ? [latin, latinBold] : [urdu, urduBold],
    );
  }

  /// Text that picks the right face and direction for its script.
  pw.Widget text(
    String s, {
    pw.TextStyle? style,
    pw.TextAlign? textAlign,
    pw.TextDirection? textDirection,
    int? maxLines,
  }) => pw.Text(
    s,
    style: styleFor(s, style),
    textAlign: textAlign,
    textDirection:
        textDirection ??
        (hasUrdu(s) ? pw.TextDirection.rtl : pw.TextDirection.ltr),
    maxLines: maxLines,
  );
}
