import 'package:bizzvot/features/analytics/domain/analytics_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ViewsStats', () {
    test('object with totals and series', () {
      final v = ViewsStats.fromJson({
        'total': 120,
        'unique': 80,
        'series': [
          {'date': '2026-10-02', 'count': 7, 'unique': 5},
          {'date': '2026-10-01', 'count': 3, 'unique': 2},
        ],
      });
      expect(v.total, 120);
      expect(v.unique, 80);
      expect(v.series.map((p) => p.count), [3, 7]); // sorted by date
      expect(v.series.first.date, DateTime(2026, 10, 1));
      expect(v.series.last.unique, 5);
    });

    test('alternate keys, Mongo {_id:{year,month,day}} and derived total', () {
      final v = ViewsStats.fromJson({
        'uniqueVisitors': '9',
        'daily': [
          {
            '_id': {'year': 2026, 'month': 10, 'day': 3},
            'views': 4,
            'visitorIp': '203.0.113.1',
          },
          {
            '_id': {'year': 2026, 'month': 10, 'day': 4},
            'views': 6,
          },
        ],
      });
      expect(v.total, 10);
      expect(v.unique, 9);
      expect(v.series.first.date, DateTime(2026, 10, 3));
    });

    test('bare list and bare number', () {
      final list = ViewsStats.fromJson([
        {'day': '2026-10-01', 'total': 2, 'unique': 1},
        {'day': '2026-10-02', 'total': 5, 'unique': 4},
      ]);
      expect(list.total, 7);
      expect(list.unique, 5);
      expect(ViewsStats.fromJson(42).total, 42);
      expect(ViewsStats.fromJson(null).total, 0);
    });

    test('date-keyed map series', () {
      final v = ViewsStats.fromJson({
        'total': 3,
        'series': {'2026-10-02': 2, '2026-10-01': 1},
      });
      expect(v.series.map((p) => p.count), [1, 2]);
    });
  });

  group('ReviewStats', () {
    test('map breakdown with string keys', () {
      final r = ReviewStats.fromJson({
        'total': 10,
        'average': 4.2,
        'breakdown': {'5': 6, '4': 2, '3': 1, '1': 1, 'junk': 99},
      });
      expect(r.total, 10);
      expect(r.average, 4.2);
      expect(r.breakdown, {1: 1, 2: 0, 3: 1, 4: 2, 5: 6});
    });

    test('list of {rating,count} and derived average/total', () {
      final r = ReviewStats.fromJson({
        'distribution': [
          {'_id': 5, 'count': 2},
          {'rating': 3, 'count': 2},
        ],
      });
      expect(r.total, 4);
      expect(r.average, 4.0);
      expect(r.breakdown[5], 2);
    });

    test('numeric array breakdown [1★..5★] and series', () {
      final r = ReviewStats.fromJson({
        'averageRating': '3.5',
        'ratings': [1, 0, 0, 0, 1],
        'series': [
          {'date': '2026-10-01', 'count': 2},
        ],
      });
      expect(r.breakdown, {1: 1, 2: 0, 3: 0, 4: 0, 5: 1});
      expect(r.average, 3.5);
      expect(r.newInPeriod, 2);
    });

    test('empty payload is safe', () {
      final r = ReviewStats.fromJson(null);
      expect(r.total, 0);
      expect(r.average, isNull);
    });
  });

  group('LinkClicks', () {
    test('items list → categories summed and sorted desc', () {
      final l = LinkClicks.fromJson({
        'items': [
          {'type': 'whatsapp', 'count': 3},
          {'type': 'instagram', 'count': 4},
          {'type': 'linkedin', 'count': 2},
          {'type': 'call', 'count': 1},
          {'type': 'company_phone', 'count': 1},
          {'type': 'vcard', 'count': 5},
          {'type': 'map', 'count': 1},
          {'type': 'custom', 'count': 0},
        ],
      });
      expect(l.counts, [
        (LinkCategory.social, 6),
        (LinkCategory.vcard, 5),
        (LinkCategory.whatsapp, 3),
        (LinkCategory.phone, 2),
        (LinkCategory.other, 1),
      ]);
      expect(l.total, 17);
    });

    test('flat map, ignoring meta keys', () {
      final l = LinkClicks.fromJson({
        'whatsapp': 2,
        'email': '3',
        'website': 1,
        'total': 6,
      });
      expect(l.counts.first, (LinkCategory.email, 3));
      expect(l.counts.map((e) => e.$1), isNot(contains(LinkCategory.other)));
    });

    test('bare list with _id / clicks keys and nested map', () {
      expect(
        LinkClicks.fromJson([
          {'_id': 'save_contact', 'clicks': 2},
          {'_id': 'custom_link', 'clicks': 1},
        ]).counts,
        [(LinkCategory.vcard, 2), (LinkCategory.custom, 1)],
      );
      expect(
        LinkClicks.fromJson({
          'byType': {'phone': 4},
        }).counts,
        [(LinkCategory.phone, 4)],
      );
    });

    test('category parsing', () {
      expect(LinkCategory.parse('WhatsApp'), LinkCategory.whatsapp);
      expect(LinkCategory.parse('tel'), LinkCategory.phone);
      expect(LinkCategory.parse('mailto'), LinkCategory.email);
      expect(LinkCategory.parse('x'), LinkCategory.social);
      expect(LinkCategory.parse('pdf'), LinkCategory.other);
      expect(LinkCategory.parse(null), LinkCategory.other);
    });
  });

  test('range query: range + from/to ISO dates', () {
    expect(AnalyticsRange.week.toQuery(DateTime(2026, 10, 11, 15, 30)), {
      'range': '7d',
      'from': '2026-10-05',
      'to': '2026-10-11',
    });
    expect(
      AnalyticsRange.quarter.toQuery(DateTime(2026, 3, 1))['from'],
      '2025-12-02',
    );
  });
}
