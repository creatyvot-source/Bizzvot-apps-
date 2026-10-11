import '../../../core/utilities/json.dart';
import '../../../core/utilities/validators.dart';
import 'commerce_models.dart' show safeHttpsUri;
import 'formatting.dart';

// ---------------------------------------------------------------------------
// NFC personalisation (physical products)
// ---------------------------------------------------------------------------

/// What an NFC tag opens when tapped.
enum NfcTarget {
  /// A Bizzvot digital card of the organization (`cardId` / `slug`).
  card,

  /// A Google review link, or the review page of a Bizzvot card.
  review,

  none;

  String get wire => switch (this) {
    NfcTarget.card => 'card',
    NfcTarget.review => 'review',
    NfcTarget.none => 'none',
  };

  static NfcTarget parse(Object? v) => switch (wireKey(str(v))) {
    'card' || 'digital_card' || 'profile' => NfcTarget.card,
    'review' ||
    'google_review' ||
    'review_card' ||
    'review_url' => NfcTarget.review,
    _ => NfcTarget.none,
  };
}

/// Which personalisation inputs an item needs. Sent by the server on the
/// catalogue item as `personalization: { nfcTarget, perUnit, printName,
/// printDesignation, logo, required }`.
class PersonalizationSpec {
  const PersonalizationSpec({
    this.target = NfcTarget.none,
    this.perUnit = false,
    this.printName = false,
    this.printDesignation = false,
    this.logo = false,
    this.required = false,
  });

  final NfcTarget target;

  /// Each unit is personalised separately (e.g. 10 staff ID cards).
  final bool perUnit;
  final bool printName;
  final bool printDesignation;
  final bool logo;

  /// Whether details must be given before checkout (else "assign later").
  final bool required;

  static const none = PersonalizationSpec();

  bool get isNone =>
      target == NfcTarget.none && !printName && !printDesignation && !logo;

  factory PersonalizationSpec.fromItemJson(Json item) {
    final raw = item['personalization'] ?? item['personalisation'];
    if (raw is Map) {
      final j = asJson(raw);
      return PersonalizationSpec(
        target: NfcTarget.parse(j['nfcTarget'] ?? j['target'] ?? j['link']),
        perUnit: boolOr(j['perUnit']),
        printName: boolOr(j['printName'] ?? j['name']),
        printDesignation: boolOr(j['printDesignation'] ?? j['designation']),
        logo: boolOr(j['logo'] ?? j['logoUpload']),
        required: boolOr(j['required']),
      );
    }
    // Stop-gap when the server only flags the item as NFC.
    if (boolOr(item['nfc'] ?? item['isNfc'])) {
      final text = '${str(item['slug']) ?? ''} ${str(item['title']) ?? ''}'
          .toLowerCase();
      final review = text.contains('review');
      return PersonalizationSpec(
        target: review ? NfcTarget.review : NfcTarget.card,
        perUnit: !review,
        printName: !review,
        printDesignation: !review,
        logo: true,
      );
    }
    return none;
  }
}

/// Personalisation of one physical unit.
class UnitPersonalization {
  const UnitPersonalization({
    this.cardId,
    this.cardSlug,
    this.cardLabel,
    this.reviewUrl,
    this.useCardReviewPage = false,
    this.printName,
    this.printDesignation,
    this.logoMediaId,
    this.logoUrl,
  });

  final String? cardId;
  final String? cardSlug;

  /// Display snapshot of the linked card (name); not sent.
  final String? cardLabel;

  /// https Google review link the tag opens.
  final String? reviewUrl;

  /// Review target is the linked card's Bizzvot review page.
  final bool useCardReviewPage;
  final String? printName;
  final String? printDesignation;
  final String? logoMediaId;
  final String? logoUrl;

  bool get isEmpty =>
      cardId == null &&
      reviewUrl == null &&
      printName == null &&
      printDesignation == null &&
      logoMediaId == null &&
      logoUrl == null;

  /// Validation message for [spec], or null when complete.
  String? problem(PersonalizationSpec spec) {
    switch (spec.target) {
      case NfcTarget.card:
        if (cardId == null) return 'Choose the card this tag opens';
      case NfcTarget.review:
        if (useCardReviewPage) {
          if (cardId == null) return 'Choose the card whose review page opens';
        } else if (reviewUrl == null || safeHttpsUri(reviewUrl) == null) {
          return 'Enter a valid https:// review link';
        }
      case NfcTarget.none:
        break;
    }
    return null;
  }

  Json toJson(NfcTarget target) => compact({
    'nfcTarget': target == NfcTarget.none ? null : target.wire,
    'cardId': cardId,
    'cardSlug': cardSlug,
    'reviewUrl': useCardReviewPage ? null : reviewUrl,
    'reviewTarget': target == NfcTarget.review
        ? (useCardReviewPage ? 'review_card' : 'google_review')
        : null,
    'printName': printName,
    'printDesignation': printDesignation,
    'logoMediaId': logoMediaId,
    'logoUrl': logoUrl,
  });
}

/// Personalisation for a cart line: one entry per unit (or a single shared
/// entry when the spec is not per-unit), or "assign later".
class LinePersonalization {
  const LinePersonalization({
    required this.spec,
    this.assignLater = false,
    this.units = const [],
  });

  final PersonalizationSpec spec;
  final bool assignLater;
  final List<UnitPersonalization> units;

  int get assignedCount => units.where((u) => !u.isEmpty).length;

  /// First validation problem across units, or null.
  String? problem(int quantity) {
    if (assignLater) return null;
    if (units.isEmpty)
      return 'Add personalisation details or choose “assign later”';
    if (spec.perUnit && units.length != quantity) {
      return 'Personalise all $quantity units or choose “assign later”';
    }
    for (var i = 0; i < units.length; i++) {
      final p = units[i].problem(spec);
      if (p != null) return spec.perUnit ? 'Unit ${i + 1}: $p' : p;
    }
    return null;
  }

  /// Keeps per-unit entries in step with quantity changes.
  LinePersonalization resized(int quantity) {
    if (!spec.perUnit) return this;
    if (units.length == quantity) return this;
    final next = units.length > quantity
        ? units.sublist(0, quantity)
        : [
            ...units,
            for (var i = units.length; i < quantity; i++)
              const UnitPersonalization(),
          ];
    return LinePersonalization(
      spec: spec,
      assignLater: assignLater,
      units: next,
    );
  }

  /// Non-per-unit specs hold a single shared entry.
  LinePersonalization withAtLeastOne() => units.isNotEmpty
      ? this
      : LinePersonalization(
          spec: spec,
          assignLater: assignLater,
          units: const [UnitPersonalization()],
        );

  LinePersonalization copyWith({
    bool? assignLater,
    List<UnitPersonalization>? units,
  }) => LinePersonalization(
    spec: spec,
    assignLater: assignLater ?? this.assignLater,
    units: units ?? this.units,
  );

  Json toJson() => {
    'assignLater': assignLater,
    if (!assignLater) 'units': [for (final u in units) u.toJson(spec.target)],
  };
}

// ---------------------------------------------------------------------------
// Shipping & GST
// ---------------------------------------------------------------------------

/// Indian states and union territories (place of supply / address state).
const indianStates = <String>[
  'Andaman and Nicobar Islands',
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chandigarh',
  'Chhattisgarh',
  'Dadra and Nagar Haveli and Daman and Diu',
  'Delhi',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jammu and Kashmir',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Ladakh',
  'Lakshadweep',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Puducherry',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
];

abstract final class ShippingValidators {
  static final _pin = RegExp(r'^[1-9][0-9]{5}$');
  static final _mobile = RegExp(r'^(?:\+?91[\s-]?)?[6-9][0-9]{9}$');
  static final _gstin = RegExp(
    r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
  );

  static String? pinCode(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'PIN code is required';
    return _pin.hasMatch(s) ? null : 'Enter a valid 6-digit PIN code';
  }

  static String? mobile(String? v) {
    final s = (v ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (s.isEmpty) return 'Phone number is required';
    return _mobile.hasMatch(s) ? null : 'Enter a valid 10-digit mobile number';
  }

  /// GSTIN is optional; when given it must be a valid 15-character GSTIN.
  static String? optionalGstin(String? v) {
    final s = v?.trim().toUpperCase() ?? '';
    if (s.isEmpty) return null;
    return _gstin.hasMatch(s) ? null : 'Enter a valid 15-character GSTIN';
  }

  static String? reviewUrl(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Review link is required';
    return safeHttpsUri(s) != null && Validators.isSafeWebUrl(s)
        ? null
        : 'Enter a valid https:// link';
  }
}

class ShippingAddress {
  const ShippingAddress({
    required this.name,
    required this.phone,
    required this.line1,
    required this.city,
    required this.state,
    required this.pinCode,
    this.line2,
    this.country = 'IN',
    this.id,
  });

  /// Server id when the address came from (or was saved to) the server.
  final String? id;
  final String name;
  final String phone;
  final String line1;
  final String? line2;
  final String city;
  final String state;
  final String pinCode;

  /// ISO 3166-1 alpha-2; shipping is India-only for now.
  final String country;

  bool get isValid =>
      name.trim().isNotEmpty &&
      ShippingValidators.mobile(phone) == null &&
      line1.trim().isNotEmpty &&
      city.trim().isNotEmpty &&
      indianStates.contains(state) &&
      ShippingValidators.pinCode(pinCode) == null;

  /// Identity for de-duplicating saved addresses.
  String get dedupeKey => [
    name,
    line1,
    line2 ?? '',
    city,
    pinCode,
  ].map((s) => s.trim().toLowerCase()).join('|');

  String get singleLine => [
    line1,
    line2,
    city,
    '$state $pinCode',
  ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');

  Json toJson() => compact({
    'id': id,
    'name': name.trim(),
    'phone': phone.trim(),
    'line1': line1.trim(),
    'line2': (line2?.trim().isEmpty ?? true) ? null : line2!.trim(),
    'city': city.trim(),
    'state': state,
    'pinCode': pinCode.trim(),
    'country': country,
  });

  static ShippingAddress? tryParse(Object? raw) {
    final j = asJson(raw);
    if (j.isEmpty) return null;
    final line1 = str(j['line1'] ?? j['addressLine1'] ?? j['address1']);
    if (line1 == null) return null;
    return ShippingAddress(
      id: str(j['id'] ?? j['_id']),
      name: strOr(j['name'] ?? j['fullName']),
      phone: strOr(j['phone']),
      line1: line1,
      line2: str(j['line2'] ?? j['addressLine2'] ?? j['address2']),
      city: strOr(j['city']),
      state: strOr(j['state']),
      pinCode: strOr(
        j['pinCode'] ?? j['pincode'] ?? j['postalCode'] ?? j['zip'],
      ),
      country: strOr(j['country'], 'IN'),
    );
  }
}

/// GST invoice details captured at checkout.
class GstDetails {
  const GstDetails({this.gstin, this.placeOfSupply, this.businessName});

  final String? gstin;
  final String? placeOfSupply;
  final String? businessName;

  bool get isEmpty =>
      gstin == null && placeOfSupply == null && businessName == null;

  Json toJson() => compact({
    'gstin': gstin?.trim().toUpperCase(),
    'placeOfSupply': placeOfSupply,
    'businessName': businessName?.trim(),
  });

  static GstDetails? tryParse(Object? raw) {
    final j = asJson(raw);
    final g = GstDetails(
      gstin: str(j['gstin'] ?? j['buyerGstin']),
      placeOfSupply: str(j['placeOfSupply']),
      businessName: str(j['businessName'] ?? j['legalName']),
    );
    return g.isEmpty ? null : g;
  }
}

// ---------------------------------------------------------------------------
// Fulfilment timeline
// ---------------------------------------------------------------------------

enum FulfilmentStep {
  placed('Order placed'),
  paid('Payment confirmed'),
  design('Design & proof'),
  printing('Printing'),
  nfcProgrammed('NFC programmed'),
  shipped('Shipped'),
  delivered('Delivered');

  const FulfilmentStep(this.label);
  final String label;

  static FulfilmentStep? parse(Object? v) => switch (wireKey(str(v))) {
    'placed' || 'created' || 'order_placed' => FulfilmentStep.placed,
    'paid' || 'payment_confirmed' => FulfilmentStep.paid,
    'design' ||
    'proof' ||
    'design_proof' ||
    'awaiting_proof' ||
    'proof_approved' ||
    'design_and_proof' => FulfilmentStep.design,
    'printing' || 'in_production' || 'production' => FulfilmentStep.printing,
    'nfc_programmed' ||
    'programmed' ||
    'nfc' ||
    'encoding' => FulfilmentStep.nfcProgrammed,
    'shipped' ||
    'dispatched' ||
    'in_transit' ||
    'out_for_delivery' => FulfilmentStep.shipped,
    'delivered' || 'completed' || 'fulfilled' => FulfilmentStep.delivered,
    _ => null,
  };
}

class Fulfilment {
  const Fulfilment({
    this.current,
    this.statusRaw,
    this.reached = const {},
    this.courier,
    this.awb,
    this.trackingUrl,
    this.note,
  });

  /// Furthest step reached according to the server.
  final FulfilmentStep? current;
  final String? statusRaw;

  /// Timestamps of reached steps (null value = reached, time unknown).
  final Map<FulfilmentStep, DateTime?> reached;
  final String? courier;
  final String? awb;
  final String? trackingUrl;

  /// Server note such as "Proof sent to your email".
  final String? note;

  Uri? get safeTrackingUri => safeHttpsUri(trackingUrl);

  bool isReached(FulfilmentStep s) =>
      reached.containsKey(s) || (current != null && s.index <= current!.index);

  static Fulfilment? tryParse(Json order) {
    final raw = order['fulfilment'] ?? order['fulfillment'];
    final j = asJson(raw);
    final statusRaw =
        str(raw is Map ? j['status'] : raw) ??
        str(order['fulfilmentStatus'] ?? order['fulfillmentStatus']);
    final shipment = asJson(j['shipment'] ?? order['shipment']);
    final reached = <FulfilmentStep, DateTime?>{};
    for (final e in asJsonList(
      j['timeline'] ?? j['steps'] ?? j['events'] ?? order['timeline'],
    )) {
      final step = FulfilmentStep.parse(e['step'] ?? e['status'] ?? e['key']);
      if (step == null) continue;
      final done = boolOrNull(e['done'] ?? e['completed']) ?? true;
      if (done)
        reached[step] = dateOrNull(e['at'] ?? e['date'] ?? e['timestamp']);
    }
    var current = FulfilmentStep.parse(statusRaw);
    for (final s in reached.keys) {
      if (current == null || s.index > current.index) current = s;
    }
    final courier = str(
      shipment['courier'] ?? j['courier'] ?? order['courier'],
    );
    final awb = str(
      shipment['awb'] ?? shipment['trackingNumber'] ?? j['awb'] ?? order['awb'],
    );
    final tracking = str(
      shipment['trackingUrl'] ?? j['trackingUrl'] ?? order['trackingUrl'],
    );
    if (current == null &&
        reached.isEmpty &&
        courier == null &&
        awb == null &&
        statusRaw == null) {
      return null;
    }
    return Fulfilment(
      current: current,
      statusRaw: statusRaw,
      reached: reached,
      courier: courier,
      awb: awb,
      trackingUrl: tracking,
      note: str(j['note'] ?? j['message']),
    );
  }
}
