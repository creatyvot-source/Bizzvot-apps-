import 'package:intl/intl.dart';

import '../../../core/utilities/json.dart';

/// A server-provided monetary amount.
///
/// Stored as an integer count of **minor units** (paise, cents …) plus an
/// ISO 4217 currency code, so no floating-point error is ever introduced.
///
/// Money is display-only on the client: there are deliberately no arithmetic
/// operators. Prices, taxes, discounts and totals are always taken from the
/// server (quote / order / invoice) and never computed in the app.
///
/// Parsing contract (see [Money.tryParse]):
/// * keys named `*Minor`, `minor`, `minorUnits`, `amountMinor`, `paise`,
///   `cents`, `subunits` hold **integer minor units**;
/// * any other amount (`amount`, `value`, bare number or decimal string such
///   as `"1499.00"`) is a **decimal in major units**.
class Money {
  const Money(this.minor, this.currency);

  /// Amount in minor units (e.g. 149900 = ₹1,499.00).
  final int minor;

  /// Upper-case ISO 4217 code, or `''` when the server did not send one.
  final String currency;

  bool get isZero => minor == 0;
  bool get isNegative => minor < 0;
  bool get hasCurrency => currency.isNotEmpty;

  static const _minorKeys = [
    'amountMinor',
    'minor',
    'minorUnits',
    'amountInMinorUnits',
    'subunits',
    'paise',
    'cents',
  ];
  static const _majorKeys = ['amount', 'value', 'decimal', 'price'];
  static const _currencyKeys = ['currency', 'currencyCode', 'currency_code'];

  static final Map<String, int> _digitsCache = {};

  /// Number of fraction digits for [currency] (INR 2, JPY 0, KWD 3).
  static int digitsFor(String currency) {
    if (currency.isEmpty) return 2;
    return _digitsCache.putIfAbsent(currency, () {
      try {
        return NumberFormat.simpleCurrency(name: currency).decimalDigits ?? 2;
      } catch (_) {
        return 2;
      }
    });
  }

  /// Normalises a currency code; returns `''` for anything not shaped like
  /// an ISO 4217 code.
  static String normalizeCurrency(Object? raw) {
    final s = str(raw)?.trim().toUpperCase();
    if (s == null || !RegExp(r'^[A-Z]{3}$').hasMatch(s)) return '';
    return s;
  }

  static String _currencyOf(Json j, String? fallback) {
    for (final k in _currencyKeys) {
      final c = normalizeCurrency(j[k]);
      if (c.isNotEmpty) return c;
    }
    return normalizeCurrency(fallback);
  }

  /// Parses a money value:
  /// * `{amountMinor: 149900, currency: 'INR'}`
  /// * `{amount: '1499.00', currency: 'INR'}`
  /// * `'1499.00'` / `1499` / `1499.5` (major units; currency from [currency])
  ///
  /// Returns null when no amount is present or it cannot be parsed exactly.
  static Money? tryParse(Object? raw, {String? currency}) {
    if (raw == null || raw is bool) return null;
    if (raw is Map) {
      final j = asJson(raw);
      final cur = _currencyOf(j, currency);
      for (final k in _minorKeys) {
        final m = _minorInt(j[k]);
        if (m != null) return Money(m, cur);
      }
      for (final k in _majorKeys) {
        final v = j[k];
        if (v is Map) continue;
        final m = _majorToMinor(v, digitsFor(cur));
        if (m != null) return Money(m, cur);
      }
      return null;
    }
    final cur = normalizeCurrency(currency);
    final m = _majorToMinor(raw, digitsFor(cur));
    return m == null ? null : Money(m, cur);
  }

  /// Reads money stored under [key] in [j]. Looks for `<key>Minor` /
  /// `<key>_minor` (integer minor units) first, then `<key>` (object or
  /// decimal). Currency comes from the nested object, then `j.currency`,
  /// then [currency].
  static Money? field(Json j, String key, {String? currency}) {
    final cur = _currencyOf(j, currency);
    for (final k in ['${key}Minor', '${key}_minor', '${key}InMinorUnits']) {
      final m = _minorInt(j[k]);
      if (m != null) return Money(m, cur);
    }
    final v = j[key];
    if (v == null) return null;
    return tryParse(v, currency: cur.isEmpty ? null : cur);
  }

  /// First non-null [field] among [keys].
  static Money? firstField(Json j, List<String> keys, {String? currency}) {
    for (final k in keys) {
      final m = field(j, k, currency: currency);
      if (m != null) return m;
    }
    return null;
  }

  static int? _minorInt(Object? v) {
    if (v is int) return v;
    if (v is double && v == v.truncateToDouble() && v.abs() < 9e15) {
      return v.toInt();
    }
    if (v is String && RegExp(r'^-?\d{1,16}$').hasMatch(v.trim())) {
      return int.parse(v.trim());
    }
    return null;
  }

  static final _decimal = RegExp(r'^([+-])?(\d{1,15})(?:\.(\d+))?$');

  /// Exact decimal → minor units conversion using string arithmetic.
  /// Extra fraction digits are rounded half away from zero.
  static int? _majorToMinor(Object? v, int digits) {
    String? s;
    if (v is int) {
      s = '$v';
    } else if (v is double) {
      if (v.isNaN || v.isInfinite) return null;
      final repr = v.toString();
      s = repr.contains('e') || repr.contains('E')
          ? v.toStringAsFixed(digits + 2)
          : repr;
    } else if (v is String) {
      s = v.trim();
    }
    if (s == null || s.isEmpty) return null;
    final m = _decimal.firstMatch(s);
    if (m == null) return null;
    final negative = m.group(1) == '-';
    final whole = int.parse(m.group(2)!);
    var frac = m.group(3) ?? '';
    var roundUp = false;
    if (frac.length > digits) {
      roundUp = frac.codeUnitAt(digits) >= 0x35; // '5'
      frac = frac.substring(0, digits);
    }
    frac = frac.padRight(digits, '0');
    var factor = 1;
    for (var i = 0; i < digits; i++) {
      factor *= 10;
    }
    var minor = whole * factor + (frac.isEmpty ? 0 : int.parse(frac));
    if (roundUp) minor += 1;
    return negative ? -minor : minor;
  }

  /// Major-unit value for display only. Never use for calculations.
  double get _displayValue {
    var factor = 1;
    for (var i = 0; i < digitsFor(currency); i++) {
      factor *= 10;
    }
    return minor / factor;
  }

  /// Localised string, e.g. `₹1,499.00`. Without a currency the bare number
  /// is shown.
  String format({String? locale}) {
    final digits = digitsFor(currency);
    final f = currency.isEmpty
        ? NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: digits)
        : NumberFormat.simpleCurrency(locale: locale, name: currency);
    return f.format(_displayValue);
  }

  Json toJson() => {'amountMinor': minor, 'currency': currency};

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => format();
}
