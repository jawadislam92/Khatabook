import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'invoice_models.dart';

String methodLabel(AppLocalizations l, PaymentMethod m) => switch (m) {
  PaymentMethod.cash => l.methodCash,
  PaymentMethod.bank => l.methodBank,
  PaymentMethod.easypaisa => l.methodEasypaisa,
  PaymentMethod.jazzcash => l.methodJazzcash,
  PaymentMethod.other => l.methodOther,
};

IconData methodIcon(PaymentMethod m) => switch (m) {
  PaymentMethod.cash => Icons.payments_outlined,
  PaymentMethod.bank => Icons.account_balance_outlined,
  PaymentMethod.easypaisa ||
  PaymentMethod.jazzcash => Icons.phone_android_outlined,
  PaymentMethod.other => Icons.more_horiz,
};

/// A bill that is still open but has some money in says "Part paid".
String invoiceStatusLabel(AppLocalizations l, Invoice inv) =>
    switch (inv.status) {
      InvoiceStatus.issued when inv.receivedPaisa > 0 =>
        l.invoiceStatusPartPaid,
      InvoiceStatus.issued => l.invoiceStatusIssued,
      InvoiceStatus.paid => l.invoiceStatusPaid,
      InvoiceStatus.voided => l.invoiceStatusVoid,
    };

Color invoiceStatusColor(InvoiceStatus s) => switch (s) {
  InvoiceStatus.issued => Tokens.saffronDeep,
  InvoiceStatus.paid => Tokens.get,
  InvoiceStatus.voided => Tokens.muted,
};

/// Turns a database error into the short message the person should read.
String friendlyError(AppLocalizations l, Object e) {
  final s = e.toString();
  if (s.contains('at least one item')) return l.needOneItem;
  if (s.contains('Discount cannot exceed')) return l.discountTooBig;
  if (s.contains('Received cannot exceed')) return l.receivedTooBig;
  return l.errorGeneric;
}
