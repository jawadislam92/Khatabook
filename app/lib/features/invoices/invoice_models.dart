// Invoicing models. Money is integer paisa; quantities may be fractional
// (cable in metres), so qty is a double and line amounts are rounded once.

enum InvoiceStatus { issued, paid, voided }

enum PaymentMethod { cash, bank, easypaisa, jazzcash, other }

extension InvoiceStatusDb on InvoiceStatus {
  String get db => switch (this) {
    InvoiceStatus.issued => 'issued',
    InvoiceStatus.paid => 'paid',
    InvoiceStatus.voided => 'void',
  };
  static InvoiceStatus fromDb(String s) => InvoiceStatus.values.firstWhere(
    (v) => v.db == s,
    orElse: () => InvoiceStatus.issued,
  );
}

extension PaymentMethodDb on PaymentMethod {
  String get db => name;
  static PaymentMethod fromDb(String s) => PaymentMethod.values.firstWhere(
    (v) => v.db == s,
    orElse: () => PaymentMethod.other,
  );
}

/// Formats a quantity without trailing zeros: 2, 2.5, 12.375.
String formatQty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  var s = q.toStringAsFixed(3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// A material or charge recorded against a job before it is billed.
class JobItem {
  const JobItem({
    required this.id,
    required this.jobId,
    required this.description,
    required this.qty,
    required this.unitPricePaisa,
    this.itemId,
    this.unit,
    this.note,
  });
  final String id;
  final String jobId;
  final String? itemId;
  final String description;
  final double qty;
  final String? unit;
  final int unitPricePaisa;
  final String? note;

  int get amountPaisa => (qty * unitPricePaisa).round();

  JobItem copyWith({double? qty, int? unitPricePaisa, String? description}) =>
      JobItem(
        id: id,
        jobId: jobId,
        itemId: itemId,
        description: description ?? this.description,
        qty: qty ?? this.qty,
        unit: unit,
        unitPricePaisa: unitPricePaisa ?? this.unitPricePaisa,
        note: note,
      );
}

class InvoiceLine {
  const InvoiceLine({
    required this.id,
    required this.description,
    required this.qty,
    required this.unitPricePaisa,
    required this.amountPaisa,
    this.itemId,
    this.unit,
    this.sortOrder = 0,
  });
  final String id;
  final String? itemId;
  final String description;
  final double qty;
  final String? unit;
  final int unitPricePaisa;
  final int amountPaisa;
  final int sortOrder;
}

class Payment {
  const Payment({
    required this.id,
    required this.invoiceId,
    required this.method,
    required this.amountPaisa,
    required this.paidAt,
    this.note,
    this.voidedAt,
  });
  final String id;
  final String invoiceId;
  final PaymentMethod method;
  final int amountPaisa;
  final DateTime paidAt;
  final String? note;
  final DateTime? voidedAt;
  bool get isVoided => voidedAt != null;
}

class Invoice {
  const Invoice({
    required this.id,
    required this.spaceId,
    required this.customerId,
    required this.customerName,
    required this.number,
    required this.issuedAt,
    required this.subtotalPaisa,
    required this.discountPaisa,
    required this.taxRateBp,
    required this.taxPaisa,
    required this.totalPaisa,
    required this.receivedPaisa,
    required this.balancePaisa,
    required this.status,
    this.jobId,
    this.jobTitle,
    this.customerPhone,
    this.customerAddress,
    this.notes,
    this.termsText,
    this.lines = const [],
    this.payments = const [],
    this.voidedAt,
  });
  final String id;
  final String spaceId;
  final String? jobId;
  final String? jobTitle;
  final String customerId;
  final String customerName;
  final String? customerPhone;
  final String? customerAddress;
  final String number;
  final DateTime issuedAt;
  final int subtotalPaisa;
  final int discountPaisa;
  final int taxRateBp;
  final int taxPaisa;
  final int totalPaisa;
  final int receivedPaisa;
  final int balancePaisa;
  final InvoiceStatus status;
  final String? notes;
  final String? termsText;
  final List<InvoiceLine> lines;
  final List<Payment> payments;
  final DateTime? voidedAt;

  bool get isVoid => status == InvoiceStatus.voided;
  bool get isPaid => status == InvoiceStatus.paid;
  bool get isOpen => status == InvoiceStatus.issued;

  Invoice copyWith({
    int? receivedPaisa,
    int? balancePaisa,
    InvoiceStatus? status,
    List<Payment>? payments,
    DateTime? voidedAt,
  }) => Invoice(
    id: id,
    spaceId: spaceId,
    jobId: jobId,
    jobTitle: jobTitle,
    customerId: customerId,
    customerName: customerName,
    customerPhone: customerPhone,
    customerAddress: customerAddress,
    number: number,
    issuedAt: issuedAt,
    subtotalPaisa: subtotalPaisa,
    discountPaisa: discountPaisa,
    taxRateBp: taxRateBp,
    taxPaisa: taxPaisa,
    totalPaisa: totalPaisa,
    receivedPaisa: receivedPaisa ?? this.receivedPaisa,
    balancePaisa: balancePaisa ?? this.balancePaisa,
    status: status ?? this.status,
    notes: notes,
    termsText: termsText,
    lines: lines,
    payments: payments ?? this.payments,
    voidedAt: voidedAt ?? this.voidedAt,
  );
}

/// What the business prints on its bills.
class BusinessProfile {
  const BusinessProfile({
    required this.spaceId,
    this.nameEn = '',
    this.nameUr,
    this.tagline,
    this.address,
    this.phone,
    this.email,
    this.bankName,
    this.accountTitle,
    this.accountNumber,
    this.easypaisa,
    this.jazzcash,
    this.termsText,
    this.taxEnabled = false,
    this.taxRateBp = 0,
    this.invoicePrefix = 'INV',
  });
  final String spaceId;
  final String nameEn;
  final String? nameUr;
  final String? tagline;
  final String? address;
  final String? phone;
  final String? email;
  final String? bankName;
  final String? accountTitle;
  final String? accountNumber;
  final String? easypaisa;
  final String? jazzcash;
  final String? termsText;
  final bool taxEnabled;
  final int taxRateBp;
  final String invoicePrefix;

  bool get isComplete => nameEn.trim().isNotEmpty;
  bool get hasPaymentDetails =>
      (accountNumber?.isNotEmpty ?? false) ||
      (easypaisa?.isNotEmpty ?? false) ||
      (jazzcash?.isNotEmpty ?? false);

  String name(String lang) =>
      lang == 'ur' && (nameUr?.isNotEmpty ?? false) ? nameUr! : nameEn;

  BusinessProfile copyWith({
    String? nameEn,
    String? nameUr,
    String? tagline,
    String? address,
    String? phone,
    String? email,
    String? bankName,
    String? accountTitle,
    String? accountNumber,
    String? easypaisa,
    String? jazzcash,
    String? termsText,
    bool? taxEnabled,
    int? taxRateBp,
    String? invoicePrefix,
  }) => BusinessProfile(
    spaceId: spaceId,
    nameEn: nameEn ?? this.nameEn,
    nameUr: nameUr ?? this.nameUr,
    tagline: tagline ?? this.tagline,
    address: address ?? this.address,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    bankName: bankName ?? this.bankName,
    accountTitle: accountTitle ?? this.accountTitle,
    accountNumber: accountNumber ?? this.accountNumber,
    easypaisa: easypaisa ?? this.easypaisa,
    jazzcash: jazzcash ?? this.jazzcash,
    termsText: termsText ?? this.termsText,
    taxEnabled: taxEnabled ?? this.taxEnabled,
    taxRateBp: taxRateBp ?? this.taxRateBp,
    invoicePrefix: invoicePrefix ?? this.invoicePrefix,
  );
}

class InvoiceStats {
  const InvoiceStats({
    required this.unpaidCount,
    required this.unpaidPaisa,
    required this.monthInvoicedPaisa,
    required this.monthReceivedPaisa,
    required this.monthJobsDone,
  });
  final int unpaidCount;
  final int unpaidPaisa;
  final int monthInvoicedPaisa;
  final int monthReceivedPaisa;
  final int monthJobsDone;
  static const zero = InvoiceStats(
    unpaidCount: 0,
    unpaidPaisa: 0,
    monthInvoicedPaisa: 0,
    monthReceivedPaisa: 0,
    monthJobsDone: 0,
  );
}

class ItemUsage {
  const ItemUsage({
    required this.description,
    required this.qty,
    required this.amountPaisa,
    this.itemId,
    this.unit,
  });
  final String? itemId;
  final String description;
  final String? unit;
  final double qty;
  final int amountPaisa;
}

/// What the bill screen sends when the installer issues the invoice.
class BillRequest {
  const BillRequest({
    required this.jobId,
    this.discountPaisa = 0,
    this.receivedPaisa = 0,
    this.method = PaymentMethod.cash,
    this.notes,
  });
  final String jobId;
  final int discountPaisa;
  final int receivedPaisa;
  final PaymentMethod method;
  final String? notes;
}

/// Pure totals maths shared by the bill screen and the preview repository,
/// mirroring issue_invoice() in the database.
class BillMath {
  const BillMath._();

  static int subtotal(Iterable<JobItem> items) =>
      items.fold(0, (sum, i) => sum + i.amountPaisa);

  static int tax(int subtotal, int discount, BusinessProfile? profile) {
    if (profile == null || !profile.taxEnabled) return 0;
    return ((subtotal - discount) * profile.taxRateBp / 10000).round();
  }
}
