import 'package:flutter_test/flutter_test.dart';
import 'package:khatabook/core/utils/money.dart';

void main() {
  group('Money.format', () {
    test('groups digits the Pakistani way', () {
      expect(Money.format(0), '0');
      expect(Money.format(500), '5');
      expect(Money.format(123400), '1,234');
      expect(Money.format(1234500), '12,345');
      expect(Money.format(12345600), '1,23,456');
      expect(Money.format(123456700), '12,34,567');
      expect(Money.format(1234567800), '1,23,45,678');
      expect(Money.format(10000000000), '10,00,00,000');
    });

    test('shows paisa only when present', () {
      expect(Money.format(123450), '1,234.50');
      expect(Money.format(5), '0.05');
      expect(Money.format(500, alwaysShowPaisa: true), '5.00');
    });

    test('handles negatives', () {
      expect(Money.format(-250000), '-2,500');
      expect(Money.format(-5), '-0.05');
    });
  });

  group('Money.parse', () {
    test('reads typed amounts', () {
      expect(Money.parse('12500'), 1250000);
      expect(Money.parse('12,500'), 1250000);
      expect(Money.parse('Rs 12,500.50'), 1250050);
      expect(Money.parse('12,500.5'), 1250050);
      expect(Money.parse('.75'), 75);
      expect(Money.parse('-300'), -30000);
      expect(Money.parse('1,00,000'), 10000000);
    });

    test('rejects junk', () {
      expect(Money.parse(''), isNull);
      expect(Money.parse('abc'), isNull);
      expect(Money.parse('-'), isNull);
      expect(Money.parse('1.2.3'), isNull);
    });

    test('round trips', () {
      for (final v in [0, 1, 99, 100, 123456789, 1000000000]) {
        expect(Money.parse(Money.format(v)), v);
      }
    });
  });
}
