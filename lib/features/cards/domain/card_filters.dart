import '../../../shared/models/card.dart';

enum CardStatusFilter {
  all('All'),
  active('Active'),
  disabled('Disabled'),
  disabledByBilling('Disabled by billing');

  const CardStatusFilter(this.label);
  final String label;

  bool matches(CardModel c) => switch (this) {
    CardStatusFilter.all => true,
    CardStatusFilter.active => c.isActive,
    CardStatusFilter.disabled => !c.isActive && !c.disabledByBilling,
    CardStatusFilter.disabledByBilling => !c.isActive && c.disabledByBilling,
  };
}

/// Case-insensitive search across names, designation, company and email.
List<CardModel> filterCards(
  List<CardModel> cards, {
  String query = '',
  CardStatusFilter status = CardStatusFilter.all,
}) {
  final q = query.trim().toLowerCase();
  return cards
      .where((c) {
        if (!status.matches(c)) return false;
        if (q.isEmpty) return true;
        return [
          c.title,
          c.staffName,
          c.designation,
          c.company,
          c.email,
          c.slug,
        ].whereType<String>().any((v) => v.toLowerCase().contains(q));
      })
      .toList(growable: false);
}

/// User-facing status label.
String cardStatusLabel(CardModel c) => c.isActive
    ? 'Active'
    : (c.disabledByBilling ? 'Disabled by billing' : 'Disabled');

/// Short visibility label for chips.
String cardVisibilityShortLabel(CardVisibility v) => switch (v) {
  CardVisibility.inherit => 'Inherit',
  CardVisibility.public => 'Public',
  CardVisibility.private => 'Private',
};
