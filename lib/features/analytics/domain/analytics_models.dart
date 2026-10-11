import '../../../core/utilities/json.dart';

/// Reporting window. Sent as `range=<n>d` plus `from`/`to` (ISO dates);
/// the exact query contract is an assumption pending backend confirmation.
enum AnalyticsRange {
  week(7, '7 days'),
  month(30, '30 days'),
  quarter(90, '90 days');

  const AnalyticsRange(this.days, this.label);
  final int days;
  final String label;

  Map<String, dynamic> toQuery(DateTime now) {
    final to = DateTime(now.year, now.month, now.day);
    final from = to.subtract(Duration(days: days - 1));
    String d(DateTime x) =>
        '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    return {'range': '${days}d', 'from': d(from), 'to': d(to)};
  }
}

/// One aggregated day. Only counts are kept — never visitor identifiers.
class DailyPoint {
  const DailyPoint({required this.date, required this.count, this.unique});

  final DateTime date;
  final int count;
  final int? unique;
}

/// Parses a time series from `[{date|day|_id, count|views|total, unique}]`.
/// `_id` may be a date string or a Mongo `{year, month, day}` group key.
List<DailyPoint> parseSeries(Object? raw) {
  if (raw is Map) {
    // `{ "2026-01-01": 3, ... }`
    final points = <DailyPoint>[];
    asJson(raw).forEach((k, v) {
      final date = DateTime.tryParse(k);
      final count = v is Map
          ? intOrNull(asJson(v)['count'] ?? asJson(v)['views'])
          : intOrNull(v);
      if (date != null && count != null) {
        points.add(
          DailyPoint(
            date: date,
            count: count,
            unique: v is Map ? intOrNull(asJson(v)['unique']) : null,
          ),
        );
      }
    });
    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
  }
  final points = <DailyPoint>[];
  for (final j in asJsonList(raw)) {
    final date = _date(j['date'] ?? j['day'] ?? j['_id'] ?? j['label']);
    if (date == null) continue;
    points.add(
      DailyPoint(
        date: date,
        count: intOr(j['count'] ?? j['views'] ?? j['total'] ?? j['value']),
        unique: intOrNull(
          j['unique'] ?? j['uniqueVisitors'] ?? j['uniqueViews'],
        ),
      ),
    );
  }
  points.sort((a, b) => a.date.compareTo(b.date));
  return points;
}

DateTime? _date(Object? v) {
  if (v is Map) {
    final j = asJson(v);
    final y = intOrNull(j['year']);
    final m = intOrNull(j['month']);
    final d = intOrNull(j['day']);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }
  final s = str(v);
  if (s == null) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  // Date-only strings are local calendar days; timestamps convert to local.
  return s.length <= 10 ? parsed : parsed.toLocal();
}

Object? _firstList(Json j, List<String> keys) {
  for (final k in keys) {
    final v = j[k];
    if (v is List || (v is Map && v.isNotEmpty)) return v;
  }
  return null;
}

/// `GET /analytics/card/:id/views`.
class ViewsStats {
  const ViewsStats({required this.total, this.unique, this.series = const []});

  final int total;
  final int? unique;
  final List<DailyPoint> series;

  factory ViewsStats.fromJson(Object? data) {
    if (data is num) return ViewsStats(total: data.toInt());
    if (data is List) {
      final series = parseSeries(data);
      return ViewsStats(
        total: series.fold(0, (a, p) => a + p.count),
        unique: series.any((p) => p.unique != null)
            ? series.fold<int>(0, (a, p) => a + (p.unique ?? 0))
            : null,
        series: series,
      );
    }
    final j = asJson(data);
    final series = parseSeries(
      _firstList(j, const [
        'series',
        'daily',
        'timeline',
        'byDay',
        'data',
        'views',
      ]),
    );
    final total =
        intOrNull(j['total'] ?? j['totalViews'] ?? j['views'] ?? j['count']) ??
        series.fold<int>(0, (a, p) => a + p.count);
    final unique = intOrNull(
      j['unique'] ?? j['uniqueVisitors'] ?? j['uniqueViews'] ?? j['visitors'],
    );
    return ViewsStats(total: total, unique: unique, series: series);
  }
}

/// `GET /analytics/card/:id/reviews`.
class ReviewStats {
  const ReviewStats({
    required this.total,
    this.average,
    this.breakdown = const {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
    this.series = const [],
  });

  final int total;
  final double? average;

  /// Star (1–5) → count.
  final Map<int, int> breakdown;
  final List<DailyPoint> series;

  int get newInPeriod => series.fold(0, (a, p) => a + p.count);

  factory ReviewStats.fromJson(Object? data) {
    final j = asJson(data);
    final breakdown = {for (var i = 1; i <= 5; i++) i: 0};
    final raw =
        j['breakdown'] ?? j['distribution'] ?? j['ratings'] ?? j['byRating'];
    if (raw is Map) {
      asJson(raw).forEach((k, v) {
        final star = intOrNull(k.replaceAll(RegExp(r'\D'), ''));
        if (star != null && star >= 1 && star <= 5) breakdown[star] = intOr(v);
      });
    } else if (raw is List) {
      if (raw.isNotEmpty && raw.every((e) => e is num)) {
        // [count1, count2, ..., count5]
        for (var i = 0; i < raw.length && i < 5; i++) {
          breakdown[i + 1] = intOr(raw[i]);
        }
      } else {
        for (final e in asJsonList(raw)) {
          final star = intOrNull(e['rating'] ?? e['stars'] ?? e['_id']);
          if (star != null && star >= 1 && star <= 5) {
            breakdown[star] = intOr(e['count'] ?? e['total']);
          }
        }
      }
    }
    final sum = breakdown.values.fold(0, (a, b) => a + b);
    final weighted = breakdown.entries.fold(0, (a, e) => a + e.key * e.value);
    final total =
        intOrNull(j['total'] ?? j['totalReviews'] ?? j['count']) ?? sum;
    final average =
        doubleOrNull(j['average'] ?? j['averageRating'] ?? j['avg']) ??
        (sum > 0 ? weighted / sum : null);
    return ReviewStats(
      total: total,
      average: average,
      breakdown: breakdown,
      series: parseSeries(
        _firstList(j, const ['series', 'daily', 'timeline', 'byDay']),
      ),
    );
  }
}

/// Link-click categories shown to organization users.
enum LinkCategory {
  whatsapp('WhatsApp'),
  phone('Phone'),
  email('Email'),
  website('Website'),
  social('Social'),
  custom('Custom links'),
  vcard('vCard'),
  other('Other');

  const LinkCategory(this.label);
  final String label;

  static const _social = {
    'social',
    'instagram',
    'facebook',
    'linkedin',
    'x',
    'twitter',
    'youtube',
    'tiktok',
    'snapchat',
    'pinterest',
    'threads',
    'telegram',
    'github',
  };

  static LinkCategory parse(String? raw) {
    final t = (raw ?? '').toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    if (t.isEmpty) return other;
    if (t.contains('whatsapp')) return whatsapp;
    if (t == 'phone' || t == 'call' || t == 'tel' || t.contains('phone')) {
      return phone;
    }
    if (t == 'email' || t == 'mail' || t == 'mailto') return email;
    if (t == 'website' || t == 'web' || t == 'site' || t == 'url') {
      return website;
    }
    if (t.contains('vcard') || t == 'savecontact' || t == 'contact') {
      return vcard;
    }
    if (t == 'custom' ||
        t == 'customlink' ||
        t == 'customlinks' ||
        t == 'link') {
      return custom;
    }
    if (_social.contains(t) || t.startsWith('social')) return social;
    return other;
  }
}

class LinkClicks {
  const LinkClicks(this.counts);

  /// Non-zero categories, sorted by count descending.
  final List<(LinkCategory, int)> counts;

  int get total => counts.fold(0, (a, e) => a + e.$2);

  /// Accepts `{items: [{type, count}]}`, a bare list, or a
  /// `{whatsapp: 3, phone: 1}` map.
  factory LinkClicks.fromJson(Object? data) {
    final totals = <LinkCategory, int>{};
    void add(Object? type, Object? count) {
      final c = intOr(count);
      if (c <= 0) return;
      final cat = LinkCategory.parse(str(type));
      totals[cat] = (totals[cat] ?? 0) + c;
    }

    Object? list = data;
    if (data is Map) {
      final j = asJson(data);
      list = _firstList(j, const [
        'items',
        'links',
        'clicks',
        'byType',
        'breakdown',
        'data',
      ]);
      if (list == null) {
        const meta = {'total', 'count', 'sum', 'range', 'from', 'to', 'cardid'};
        j.forEach((k, v) {
          if ((v is num || v is String) && !meta.contains(k.toLowerCase())) {
            add(k, v);
          }
        });
      }
    }
    if (list is Map) {
      asJson(list).forEach(add);
    } else if (list is List) {
      for (final e in asJsonList(list)) {
        add(
          e['type'] ?? e['_id'] ?? e['linkType'] ?? e['eventType'] ?? e['name'],
          e['count'] ?? e['clicks'] ?? e['total'],
        );
      }
    }
    final sorted = totals.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) {
        final c = b.$2.compareTo(a.$2);
        return c != 0 ? c : a.$1.index.compareTo(b.$1.index);
      });
    return LinkClicks(List.unmodifiable(sorted));
  }
}
