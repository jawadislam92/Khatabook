/// Spells whole rupee amounts in words, in English and Urdu, using the
/// South Asian scale (hazaar, lakh, crore). Used in simple mode under amounts.
class NumberWords {
  const NumberWords._();

  static const _enOnes = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];
  static const _enTens = [
    '',
    '',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
  ];

  // Urdu has a distinct word for every number from 0 to 99.
  static const _ur = [
    'صفر',
    'ایک',
    'دو',
    'تین',
    'چار',
    'پانچ',
    'چھ',
    'سات',
    'آٹھ',
    'نو',
    'دس',
    'گیارہ',
    'بارہ',
    'تیرہ',
    'چودہ',
    'پندرہ',
    'سولہ',
    'سترہ',
    'اٹھارہ',
    'انیس',
    'بیس',
    'اکیس',
    'بائیس',
    'تئیس',
    'چوبیس',
    'پچیس',
    'چھبیس',
    'ستائیس',
    'اٹھائیس',
    'انتیس',
    'تیس',
    'اکتیس',
    'بتیس',
    'تینتیس',
    'چونتیس',
    'پینتیس',
    'چھتیس',
    'سینتیس',
    'اڑتیس',
    'انتالیس',
    'چالیس',
    'اکتالیس',
    'بیالیس',
    'تینتالیس',
    'چوالیس',
    'پینتالیس',
    'چھیالیس',
    'سینتالیس',
    'اڑتالیس',
    'انچاس',
    'پچاس',
    'اکاون',
    'باون',
    'ترپن',
    'چون',
    'پچپن',
    'چھپن',
    'ستاون',
    'اٹھاون',
    'انسٹھ',
    'ساٹھ',
    'اکسٹھ',
    'باسٹھ',
    'تریسٹھ',
    'چونسٹھ',
    'پینسٹھ',
    'چھیاسٹھ',
    'سڑسٹھ',
    'اڑسٹھ',
    'انہتر',
    'ستر',
    'اکہتر',
    'بہتر',
    'تہتر',
    'چوہتر',
    'پچہتر',
    'چھہتر',
    'ستتر',
    'اٹھتر',
    'اناسی',
    'اسی',
    'اکیاسی',
    'بیاسی',
    'تراسی',
    'چوراسی',
    'پچاسی',
    'چھیاسی',
    'ستاسی',
    'اٹھاسی',
    'نواسی',
    'نوے',
    'اکانوے',
    'بانوے',
    'ترانوے',
    'چورانوے',
    'پچانوے',
    'چھیانوے',
    'ستانوے',
    'اٹھانوے',
    'ننانوے',
  ];

  /// Words for a whole number of rupees in the given language code.
  static String rupees(int rupees, String languageCode) {
    final ur = languageCode == 'ur';
    if (rupees < 0) {
      final body = ur ? _urWords(-rupees) : _enWords(-rupees);
      return ur ? 'منفی $body' : 'minus $body';
    }
    return ur ? _urWords(rupees) : _enWords(rupees);
  }

  static String _enBelowHundred(int n) {
    if (n < 20) return _enOnes[n];
    final t = _enTens[n ~/ 10];
    final o = n % 10;
    return o == 0 ? t : '$t ${_enOnes[o]}';
  }

  static String _enBelowThousand(int n) {
    if (n < 100) return _enBelowHundred(n);
    final h = '${_enOnes[n ~/ 100]} hundred';
    final r = n % 100;
    return r == 0 ? h : '$h ${_enBelowHundred(r)}';
  }

  static String _enWords(int n) {
    if (n == 0) return _enOnes[0];
    final parts = <String>[];
    final crore = n ~/ 10000000;
    final lakh = (n ~/ 100000) % 100;
    final thousand = (n ~/ 1000) % 100;
    final rest = n % 1000;
    if (crore > 0) parts.add('${_enWords(crore)} crore');
    if (lakh > 0) parts.add('${_enBelowHundred(lakh)} lakh');
    if (thousand > 0) parts.add('${_enBelowHundred(thousand)} thousand');
    if (rest > 0) parts.add(_enBelowThousand(rest));
    return parts.join(' ');
  }

  static String _urBelowThousand(int n) {
    if (n < 100) return _ur[n];
    final h = '${_ur[n ~/ 100]} سو';
    final r = n % 100;
    return r == 0 ? h : '$h ${_ur[r]}';
  }

  static String _urWords(int n) {
    if (n == 0) return _ur[0];
    final parts = <String>[];
    final crore = n ~/ 10000000;
    final lakh = (n ~/ 100000) % 100;
    final thousand = (n ~/ 1000) % 100;
    final rest = n % 1000;
    if (crore > 0) parts.add('${_urWords(crore)} کروڑ');
    if (lakh > 0) parts.add('${_ur[lakh]} لاکھ');
    if (thousand > 0) parts.add('${_ur[thousand]} ہزار');
    if (rest > 0) parts.add(_urBelowThousand(rest));
    return parts.join(' ');
  }
}
