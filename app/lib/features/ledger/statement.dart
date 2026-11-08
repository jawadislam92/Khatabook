import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/money.dart';
import 'ledger_models.dart';

/// Labels the statement needs, passed in so the PDF follows the app language.
class StatementLabels {
  const StatementLabels({
    required this.title,
    required this.date,
    required this.note,
    required this.gave,
    required this.got,
    required this.balance,
    required this.totalGave,
    required this.totalGot,
    required this.closing,
    required this.cancelled,
    required this.generated,
    required this.willGet,
    required this.willGive,
  });
  final String title,
      date,
      note,
      gave,
      got,
      balance,
      totalGave,
      totalGot,
      closing,
      cancelled,
      generated,
      willGet,
      willGive;
}

class Statement {
  const Statement._();

  /// Builds a one party statement. Entries are expected newest first and are
  /// re ordered oldest first with a running balance.
  static Future<Uint8List> pdf({
    required Party party,
    required List<Entry> entries,
    required StatementLabels labels,
    required String spaceName,
    required bool rtl,
  }) async {
    final urdu = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoNastaliqUrdu-Regular.ttf'),
    );
    final urduBold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoNastaliqUrdu-Bold.ttf'),
    );
    final base = pw.Font.helvetica();
    final bold = pw.Font.helveticaBold();
    final theme = pw.ThemeData.withFont(
      base: base,
      bold: bold,
      fontFallback: [urdu, urduBold],
    );
    final dir = rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    final ordered = entries.where((e) => !e.isVoided || true).toList()
      ..sort((a, b) {
        final d = a.entryDate.compareTo(b.entryDate);
        return d != 0 ? d : a.createdAt.compareTo(b.createdAt);
      });
    var running = 0;
    var totalGave = 0;
    var totalGot = 0;
    final rows = <List<String>>[];
    for (final e in ordered) {
      running += e.signedPaisa;
      if (e.direction == EntryDirection.gave) {
        totalGave += e.amountPaisa;
      } else {
        totalGot += e.amountPaisa;
      }
      rows.add([
        DateFormat('d MMM yyyy').format(e.entryDate),
        [if (e.isVoided) '[${labels.cancelled}] ', e.note ?? ''].join(),
        e.direction == EntryDirection.gave ? Money.format(e.amountPaisa) : '',
        e.direction == EntryDirection.got ? Money.format(e.amountPaisa) : '',
        _signed(running),
      ]);
    }
    final closingText = running >= 0
        ? '${labels.willGet}: Rs ${Money.format(running)}'
        : '${labels.willGive}: Rs ${Money.format(-running)}';

    final doc = pw.Document(
      theme: theme,
      title: '${labels.title} - ${party.name}',
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        margin: const pw.EdgeInsets.all(36),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  labels.title,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#0E8C7F'),
                  ),
                ),
                pw.Text(
                  spaceName,
                  style: const pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              party.name,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            if (party.phone != null)
              pw.Text(
                party.phone!,
                style: const pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey700,
                ),
              ),
            pw.SizedBox(height: 10),
            pw.Container(height: 1.5, color: PdfColor.fromHex('#0E8C7F')),
            pw.SizedBox(height: 10),
          ],
        ),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              labels.generated,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
            pw.Text(
              '${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ],
        ),
        build: (ctx) => [
          pw.TableHelper.fromTextArray(
            headers: [
              labels.date,
              labels.note,
              labels.gave,
              labels.got,
              labels.balance,
            ],
            data: rows,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              fontSize: 10,
            ),
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#213A5C'),
            ),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FlexColumnWidth(1.4),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(1.3),
              3: const pw.FlexColumnWidth(1.3),
              4: const pw.FlexColumnWidth(1.5),
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${labels.totalGave}: Rs ${Money.format(totalGave)}',
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.Text(
                  '${labels.totalGot}: Rs ${Money.format(totalGot)}',
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  closingText,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static String _signed(int paisa) =>
      paisa < 0 ? '-${Money.format(-paisa)}' : Money.format(paisa);

  /// CSV of entries for a whole space or one party, oldest first.
  static Uint8List csv({
    required List<Entry> entries,
    required Map<String, Party> parties,
  }) {
    final ordered = entries.toList()
      ..sort((a, b) => a.entryDate.compareTo(b.entryDate));
    final buf = StringBuffer();
    buf.writeln('date,party,direction,amount_rupees,note,status,added_by');
    for (final e in ordered) {
      buf.writeln(
        [
          DateFormat('yyyy-MM-dd').format(e.entryDate),
          _csvCell(parties[e.partyId]?.name ?? e.partyId),
          e.direction.name,
          Money.format(
            e.amountPaisa,
            alwaysShowPaisa: true,
          ).replaceAll(',', ''),
          _csvCell(e.note ?? ''),
          e.isVoided ? 'cancelled' : (e.isReversal ? 'reversal' : 'ok'),
          _csvCell(e.createdByName ?? ''),
        ].join(','),
      );
    }
    // UTF-8 BOM so Excel opens Urdu text correctly.
    return Uint8List.fromList([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(buf.toString()),
    ]);
  }

  static String _csvCell(String s) {
    final needs = s.contains(',') || s.contains('"') || s.contains('\n');
    final body = s.replaceAll('"', '""');
    return needs ? '"$body"' : body;
  }
}
