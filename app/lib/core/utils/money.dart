/// Money helpers. All amounts are integers in paisa (Rs 1 = 100 paisa).
/// Nothing in the app does arithmetic on doubles for money.
class Money {
  const Money._();

  /// Formats paisa as rupees with Pakistani digit grouping:
  /// 1234567 rupees -> "12,34,567". Paisa are shown only when non zero.
  static String format(int paisa, {bool alwaysShowPaisa = false}) {
    final negative = paisa < 0;
    final abs = paisa.abs();
    final rupees = abs ~/ 100;
    final rem = abs % 100;
    final grouped = groupDigits(rupees);
    final body = (rem != 0 || alwaysShowPaisa)
        ? '$grouped.${rem.toString().padLeft(2, '0')}'
        : grouped;
    return negative ? '-$body' : body;
  }

  /// South Asian grouping: last three digits, then pairs.
  static String groupDigits(int n) {
    final s = n.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var head = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (head.length > 2) {
      parts.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    parts.insert(0, head);
    return '${parts.join(',')},$last3';
  }

  /// Parses user typed rupees ("12,500", "12500.50", "Rs 1,200") into paisa.
  /// Returns null when the text is not an amount.
  static int? parse(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'[^\d.\-]'), '')
        .replaceFirst(RegExp(r'^-+'), '-');
    if (cleaned.isEmpty || cleaned == '-' || cleaned == '.') return null;
    final negative = cleaned.startsWith('-');
    final body = negative ? cleaned.substring(1) : cleaned;
    final dot = body.indexOf('.');
    final rupeesText = dot == -1 ? body : body.substring(0, dot);
    var paisaText = dot == -1 ? '' : body.substring(dot + 1);
    if (paisaText.contains('.')) return null;
    if (paisaText.length > 2) paisaText = paisaText.substring(0, 2);
    final rupees = rupeesText.isEmpty ? 0 : int.tryParse(rupeesText);
    if (rupees == null) return null;
    final paisa = paisaText.isEmpty ? 0 : int.parse(paisaText.padRight(2, '0'));
    final total = rupees * 100 + paisa;
    return negative ? -total : total;
  }
}
