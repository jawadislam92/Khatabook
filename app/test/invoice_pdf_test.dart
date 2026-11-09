import 'dart:io';

import 'package:duebook/features/invoices/invoice_models.dart';
import 'package:duebook/features/invoices/invoice_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  InvoicePdfLabels labels(bool ur) => InvoicePdfLabels(
    invoice: ur ? 'بل' : 'INVOICE',
    billTo: ur ? 'بنام' : 'Bill to',
    job: ur ? 'کام' : 'Job',
    description: ur ? 'تفصیل' : 'Description',
    qty: ur ? 'تعداد' : 'Qty',
    rate: ur ? 'ریٹ' : 'Rate',
    amount: ur ? 'رقم' : 'Amount',
    subtotal: ur ? 'ذیلی کل' : 'Subtotal',
    discount: ur ? 'رعایت' : 'Discount',
    tax: ur ? 'ٹیکس' : 'Tax',
    total: ur ? 'کل رقم' : 'Total',
    received: ur ? 'وصول' : 'Received',
    balanceDue: ur ? 'باقی رقم' : 'Balance due',
    payTo: ur ? 'ادائیگی کی تفصیلات' : 'Payment details',
    bank: 'Bank',
    accountTitle: 'Account title',
    accountNumber: 'Account number or IBAN',
    easypaisa: 'EasyPaisa',
    jazzcash: 'JazzCash',
    payments: ur ? 'ادائیگیاں' : 'Payments',
    thanks: ur ? 'آپ کے کاروبار کا شکریہ۔' : 'Thank you for your business.',
    madeWith: 'Made with Duebook',
    paidStamp: 'PAID',
    cancelledStamp: 'CANCELLED',
    methodLabel: (m) => m.name,
  );

  final invoice = Invoice(
    id: 'i1',
    spaceId: 'b',
    jobId: 'j1',
    jobTitle: '2 cameras not recording',
    customerId: 'c1',
    customerName: 'Mr Ahmed F-10',
    customerPhone: '0300 5556667',
    customerAddress: 'House 12, Street 4, F-10/2, Islamabad',
    number: 'INV-2026-0007',
    issuedAt: DateTime(2026, 11, 9, 16, 30),
    subtotalPaisa: 1335000,
    discountPaisa: 35000,
    taxRateBp: 0,
    taxPaisa: 0,
    totalPaisa: 1300000,
    receivedPaisa: 500000,
    balancePaisa: 800000,
    status: InvoiceStatus.issued,
    termsText: 'One year warranty on installation work. Goods once sold are not returned.',
    lines: const [
      InvoiceLine(
        id: 'l1',
        description: 'Dome camera 2MP',
        qty: 2,
        unit: 'pc',
        unitPricePaisa: 450000,
        amountPaisa: 900000,
      ),
      InvoiceLine(
        id: 'l2',
        description: 'Coaxial cable',
        qty: 30,
        unit: 'm',
        unitPricePaisa: 4500,
        amountPaisa: 135000,
        sortOrder: 1,
      ),
      InvoiceLine(
        id: 'l3',
        description: 'Service charge',
        qty: 2,
        unit: 'visit',
        unitPricePaisa: 150000,
        amountPaisa: 300000,
        sortOrder: 2,
      ),
    ],
    payments: [
      Payment(
        id: 'p1',
        invoiceId: 'i1',
        method: PaymentMethod.easypaisa,
        amountPaisa: 500000,
        paidAt: DateTime(2026, 11, 9, 16, 32),
      ),
    ],
  );
  const profile = BusinessProfile(
    spaceId: 'b',
    nameEn: 'Ahmed CCTV & Solar',
    nameUr: 'احمد سی سی ٹی وی اینڈ سولر',
    tagline: 'Cameras, solar, and peace of mind',
    address: 'Shop 4, Commercial Market, Rawalpindi',
    phone: '0300 1234567',
    bankName: 'Meezan Bank',
    accountTitle: 'Ahmed Khan',
    accountNumber: 'PK00MEZN0000000000000000',
    easypaisa: '0300 1234567',
  );

  test('invoice PDF renders in English and Urdu', () async {
    final en = await InvoicePdf.build(
      invoice: invoice,
      profile: profile,
      labels: labels(false),
      rtl: false,
    );
    final ur = await InvoicePdf.build(
      invoice: invoice.copyWith(status: InvoiceStatus.paid, balancePaisa: 0),
      profile: profile,
      labels: labels(true),
      rtl: true,
    );
    final out = Platform.environment['DUEBOOK_PDF_OUT'];
    if (out != null) {
      await File('$out/invoice-en.pdf').writeAsBytes(en);
      await File('$out/invoice-ur.pdf').writeAsBytes(ur);
    }
    expect(String.fromCharCodes(en.take(4)), '%PDF');
    expect(String.fromCharCodes(ur.take(4)), '%PDF');
    expect(en.length, greaterThan(3000));
    expect(ur.length, greaterThan(3000));
  });
}
