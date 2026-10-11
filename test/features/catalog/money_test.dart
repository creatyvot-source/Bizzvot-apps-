import 'package:bizzvot/features/catalog/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.tryParse', () {
    test('integer minor units', () {
      expect(Money.tryParse({'amountMinor': 149900, 'currency': 'inr'}), const Money(149900, 'INR'));
      expect(Money.tryParse({'paise': '49900', 'currency': 'INR'}), const Money(49900, 'INR'));
    });

    test('decimal strings are exact', () {
      expect(Money.tryParse({'amount': '1499.00', 'currency': 'INR'}), const Money(149900, 'INR'));
      expect(Money.tryParse('0.10', currency: 'USD'), const Money(10, 'USD'));
      expect(Money.tryParse('19.999', currency: 'USD'), const Money(2000, 'USD'));
      expect(Money.tryParse('-5.5', currency: 'INR'), const Money(-550, 'INR'));
    });

    test('bare numbers are major units; doubles do not drift', () {
      expect(Money.tryParse(499, currency: 'INR'), const Money(49900, 'INR'));
      expect(Money.tryParse(0.1 + 0.2, currency: 'INR'), const Money(30, 'INR'));
      expect(Money.tryParse(1499.99, currency: 'INR'), const Money(149999, 'INR'));
    });

    test('zero-decimal currencies', () {
      expect(Money.tryParse('1500', currency: 'JPY'), const Money(1500, 'JPY'));
      expect(Money.digitsFor('JPY'), 0);
    });

    test('rejects garbage', () {
      expect(Money.tryParse(null), isNull);
      expect(Money.tryParse(true), isNull);
      expect(Money.tryParse('12,00'), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse({'currency': 'INR'}), isNull);
      expect(Money.tryParse(double.nan), isNull);
    });

    test('invalid currency codes become unknown', () {
      expect(Money.tryParse({'amount': '1', 'currency': 'rupees'})!.currency, '');
    });
  });

  group('Money.field', () {
    test('prefers <key>Minor over decimal', () {
      final m = Money.field({'totalMinor': 59882, 'total': '1', 'currency': 'INR'}, 'total');
      expect(m, const Money(59882, 'INR'));
    });

    test('nested object with own currency', () {
      final m = Money.field({'price': {'amount': '350', 'currency': 'INR'}}, 'price');
      expect(m, const Money(35000, 'INR'));
    });

    test('scalar uses parent currency', () {
      expect(Money.field({'price': '999', 'currency': 'INR'}, 'price'), const Money(99900, 'INR'));
    });
  });

  group('format', () {
    test('uses intl simpleCurrency', () {
      expect(const Money(149900, 'INR').format(locale: 'en_IN'), '₹1,499.00');
      expect(const Money(1050, 'USD').format(locale: 'en_US'), r'$10.50');
    });

    test('no currency formats bare number', () {
      expect(const Money(12345, '').format(locale: 'en_US'), '123.45');
    });
  });
}
