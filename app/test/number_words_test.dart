import 'package:flutter_test/flutter_test.dart';
import 'package:khatabook/core/utils/number_words.dart';

void main() {
  group('English', () {
    test('small numbers', () {
      expect(NumberWords.rupees(0, 'en'), 'zero');
      expect(NumberWords.rupees(7, 'en'), 'seven');
      expect(NumberWords.rupees(15, 'en'), 'fifteen');
      expect(NumberWords.rupees(40, 'en'), 'forty');
      expect(NumberWords.rupees(42, 'en'), 'forty two');
      expect(NumberWords.rupees(100, 'en'), 'one hundred');
      expect(NumberWords.rupees(305, 'en'), 'three hundred five');
      expect(NumberWords.rupees(999, 'en'), 'nine hundred ninety nine');
    });

    test('South Asian scale', () {
      expect(NumberWords.rupees(1000, 'en'), 'one thousand');
      expect(NumberWords.rupees(5000, 'en'), 'five thousand');
      expect(NumberWords.rupees(12500, 'en'), 'twelve thousand five hundred');
      expect(
        NumberWords.rupees(99999, 'en'),
        'ninety nine thousand nine hundred ninety nine',
      );
      expect(NumberWords.rupees(100000, 'en'), 'one lakh');
      expect(NumberWords.rupees(250000, 'en'), 'two lakh fifty thousand');
      expect(
        NumberWords.rupees(1234567, 'en'),
        'twelve lakh thirty four thousand five hundred sixty seven',
      );
      expect(NumberWords.rupees(10000000, 'en'), 'one crore');
      expect(NumberWords.rupees(125000000, 'en'), 'twelve crore fifty lakh');
      expect(NumberWords.rupees(1000000000, 'en'), 'one hundred crore');
    });

    test('negative', () {
      expect(NumberWords.rupees(-500, 'en'), 'minus five hundred');
    });
  });

  group('Urdu', () {
    test('small numbers', () {
      expect(NumberWords.rupees(0, 'ur'), 'صفر');
      expect(NumberWords.rupees(1, 'ur'), 'ایک');
      expect(NumberWords.rupees(12, 'ur'), 'بارہ');
      expect(NumberWords.rupees(25, 'ur'), 'پچیس');
      expect(NumberWords.rupees(99, 'ur'), 'ننانوے');
      expect(NumberWords.rupees(100, 'ur'), 'ایک سو');
      expect(NumberWords.rupees(250, 'ur'), 'دو سو پچاس');
    });

    test('scale words', () {
      expect(NumberWords.rupees(5000, 'ur'), 'پانچ ہزار');
      expect(NumberWords.rupees(12500, 'ur'), 'بارہ ہزار پانچ سو');
      expect(NumberWords.rupees(100000, 'ur'), 'ایک لاکھ');
      expect(NumberWords.rupees(350000, 'ur'), 'تین لاکھ پچاس ہزار');
      expect(NumberWords.rupees(10000000, 'ur'), 'ایک کروڑ');
      expect(
        NumberWords.rupees(12345678, 'ur'),
        'ایک کروڑ تئیس لاکھ پینتالیس ہزار چھ سو اٹھتر',
      );
    });
  });
}
