import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/money.dart';
import '../../core/utils/pdf_fonts.dart';
import 'invoice_models.dart';

/// Labels the bill needs, passed in so the PDF follows the app language.
class InvoicePdfLabels {
  const InvoicePdfLabels({
    required this.invoice,
    required this.billTo,
    required this.job,
    required this.description,
    required this.qty,
    required this.rate,
    required this.amount,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.received,
    required this.balanceDue,
    required this.payTo,
    required this.bank,
    required this.accountTitle,
    required this.accountNumber,
    required this.easypaisa,
    required this.jazzcash,
    required this.payments,
    required this.thanks,
    required this.madeWith,
    required this.paidStamp,
    required this.cancelledStamp,
    required this.methodLabel,
  });
  final String invoice,
      billTo,
      job,
      description,
      qty,
      rate,
      amount,
      subtotal,
      discount,
      tax,
      total,
      received,
      balanceDue,
      payTo,
      bank,
      accountTitle,
      accountNumber,
      easypaisa,
      jazzcash,
      payments,
      thanks,
      madeWith,
      paidStamp,
      cancelledStamp;
  final String Function(PaymentMethod) methodLabel;
}

class InvoicePdf {
  const InvoicePdf._();

  static final _teal = PdfColor.fromHex('#0E8C7F');
  static final _navy = PdfColor.fromHex('#213A5C');
  static final _saffron = PdfColor.fromHex('#D97706');
  static final _green = PdfColor.fromHex('#15803D');

  static Future<Uint8List> build({
    required Invoice invoice,
    required BusinessProfile? profile,
    required InvoicePdfLabels labels,
    required bool rtl,
  }) async {
    final f = await PdfFonts.load();
    final theme = f.theme(rtl: rtl);
    final dir = rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final date = DateFormat('d MMM yyyy');
    final name = profile?.nameEn.trim().isNotEmpty ?? false
        ? profile!.nameEn
        : 'Duebook';

    pw.Widget money(
      String label,
      int paisa, {
      bool bold = false,
      PdfColor? color,
    }) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        f.text(
          label,
          style: pw.TextStyle(
            fontSize: bold ? 12 : 10,
            fontWeight: bold ? pw.FontWeight.bold : null,
            color: color ?? PdfColors.grey800,
          ),
        ),
        f.text(
          'Rs ${Money.format(paisa)}',
          style: pw.TextStyle(
            fontSize: bold ? 13 : 10,
            fontWeight: bold ? pw.FontWeight.bold : null,
            color: color ?? PdfColors.grey900,
          ),
        ),
      ],
    );

    const cellStyle = pw.TextStyle(fontSize: 10);
    final rows = <List<dynamic>>[
      for (var i = 0; i < invoice.lines.length; i++)
        [
          '${i + 1}',
          f.text(invoice.lines[i].description, style: cellStyle),
          '${formatQty(invoice.lines[i].qty)}${invoice.lines[i].unit == null ? '' : ' ${invoice.lines[i].unit}'}',
          Money.format(invoice.lines[i].unitPricePaisa),
          Money.format(invoice.lines[i].amountPaisa),
        ],
    ];
    final livePayments = invoice.payments.where((p) => !p.isVoided).toList();
    final payTo = <List<String>>[
      if (profile?.bankName?.isNotEmpty ?? false)
        [labels.bank, profile!.bankName!],
      if (profile?.accountTitle?.isNotEmpty ?? false)
        [labels.accountTitle, profile!.accountTitle!],
      if (profile?.accountNumber?.isNotEmpty ?? false)
        [labels.accountNumber, profile!.accountNumber!],
      if (profile?.easypaisa?.isNotEmpty ?? false)
        [labels.easypaisa, profile!.easypaisa!],
      if (profile?.jazzcash?.isNotEmpty ?? false)
        [labels.jazzcash, profile!.jazzcash!],
    ];

    final headerStyle = pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
      fontSize: 10,
    );
    final doc = pw.Document(
      theme: theme,
      title: '${labels.invoice} ${invoice.number}',
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        margin: const pw.EdgeInsets.all(36),
        footer: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(height: 0.8, color: PdfColors.grey400),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                f.text(
                  labels.thanks,
                  style: pw.TextStyle(fontSize: 9, color: _teal),
                ),
                f.text(
                  '${labels.madeWith}  ·  ${ctx.pageNumber}/${ctx.pagesCount}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          ],
        ),
        build: (ctx) => [
          // Header: business on one side, bill number on the other.
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    f.text(
                      name,
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: _teal,
                      ),
                    ),
                    if (profile?.nameUr?.isNotEmpty ?? false)
                      f.text(
                        profile!.nameUr!,
                        style: pw.TextStyle(fontSize: 13, color: _teal),
                      ),
                    if (profile?.tagline?.isNotEmpty ?? false)
                      f.text(
                        profile!.tagline!,
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey700,
                        ),
                      ),
                    pw.SizedBox(height: 4),
                    for (final line in [
                      profile?.address,
                      profile?.phone,
                      profile?.email,
                    ])
                      if (line?.isNotEmpty ?? false)
                        f.text(
                          line!,
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey800,
                          ),
                        ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  f.text(
                    labels.invoice,
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: _navy,
                      letterSpacing: 1.5,
                    ),
                  ),
                  f.text(
                    invoice.number,
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  f.text(
                    date.format(invoice.issuedAt),
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                  if (invoice.isPaid || invoice.isVoid) ...[
                    pw.SizedBox(height: 6),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                          color: invoice.isPaid ? _green : PdfColors.grey600,
                          width: 1.5,
                        ),
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: f.text(
                        invoice.isPaid
                            ? labels.paidStamp
                            : labels.cancelledStamp,
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: invoice.isPaid ? _green : PdfColors.grey600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Container(height: 2, color: _teal),
          pw.SizedBox(height: 12),
          // Customer and job.
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    f.text(
                      labels.billTo.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey600,
                        letterSpacing: 1,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    f.text(
                      invoice.customerName,
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (invoice.customerPhone?.isNotEmpty ?? false)
                      f.text(
                        invoice.customerPhone!,
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    if (invoice.customerAddress?.isNotEmpty ?? false)
                      f.text(
                        invoice.customerAddress!,
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                  ],
                ),
              ),
              if (invoice.jobTitle?.isNotEmpty ?? false)
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      f.text(
                        labels.job.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey600,
                          letterSpacing: 1,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      f.text(
                        invoice.jobTitle!,
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: [
              for (final h in [
                '#',
                labels.description,
                labels.qty,
                labels.rate,
                labels.amount,
              ])
                f.text(h, style: headerStyle),
            ],
            data: rows,
            headerStyle: headerStyle,
            headerDecoration: pw.BoxDecoration(color: _navy),
            cellStyle: cellStyle,
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FlexColumnWidth(0.5),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.4),
              4: const pw.FlexColumnWidth(1.6),
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (livePayments.isNotEmpty) ...[
                      f.text(
                        labels.payments.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey600,
                          letterSpacing: 1,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      for (final p in livePayments)
                        f.text(
                          '${date.format(p.paidAt)}  ·  ${labels.methodLabel(p.method)}  ·  Rs ${Money.format(p.amountPaisa)}',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      pw.SizedBox(height: 10),
                    ],
                    if (payTo.isNotEmpty && invoice.balancePaisa > 0) ...[
                      f.text(
                        labels.payTo.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey600,
                          letterSpacing: 1,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      for (final kv in payTo)
                        f.text(
                          '${kv[0]}: ${kv[1]}',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(width: 24),
              pw.Container(
                width: 220,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  children: [
                    money(labels.subtotal, invoice.subtotalPaisa),
                    if (invoice.discountPaisa > 0) ...[
                      pw.SizedBox(height: 3),
                      money(labels.discount, -invoice.discountPaisa),
                    ],
                    if (invoice.taxPaisa > 0) ...[
                      pw.SizedBox(height: 3),
                      money(
                        '${labels.tax} (${invoice.taxRateBp / 100}%)',
                        invoice.taxPaisa,
                      ),
                    ],
                    pw.SizedBox(height: 6),
                    pw.Container(height: 0.8, color: PdfColors.grey400),
                    pw.SizedBox(height: 6),
                    money(labels.total, invoice.totalPaisa, bold: true),
                    if (invoice.receivedPaisa > 0) ...[
                      pw.SizedBox(height: 3),
                      money(
                        labels.received,
                        invoice.receivedPaisa,
                        color: _green,
                      ),
                    ],
                    if (!invoice.isVoid) ...[
                      pw.SizedBox(height: 3),
                      money(
                        labels.balanceDue,
                        invoice.balancePaisa,
                        bold: true,
                        color: invoice.balancePaisa > 0 ? _saffron : _green,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (invoice.notes?.isNotEmpty ?? false) ...[
            pw.SizedBox(height: 14),
            f.text(invoice.notes!, style: const pw.TextStyle(fontSize: 9)),
          ],
          if (invoice.termsText?.isNotEmpty ?? false) ...[
            pw.SizedBox(height: 14),
            f.text(
              invoice.termsText!,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }
}
