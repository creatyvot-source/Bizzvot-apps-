import '../../../core/utilities/json.dart';
import '../../../core/utilities/validators.dart';
import 'formatting.dart';
import 'money.dart';

/// Catalogue section. [wire] is the path segment used by
/// `GET /catalog/:type/:id` and `Routes.ownerShopItem(type, id)`.
enum CatalogItemType {
  service('services', 'Service'),
  product('products', 'Product'),
  plan('plans', 'Plan'),
  unknown('items', 'Item');

  const CatalogItemType(this.wire, this.label);
  final String wire;
  final String label;

  static CatalogItemType parse(Object? v) => switch (wireKey(str(v))) {
        'service' || 'services' => CatalogItemType.service,
        'product' || 'products' => CatalogItemType.product,
        'plan' || 'plans' => CatalogItemType.plan,
        _ => CatalogItemType.unknown,
      };
}

/// App-store payment classification (plan §12.6).
///
/// TODO(policy): Apple App Store / Google Play rules differ by category and
/// storefront. Before release, confirm with the backend + legal which items
/// fall into each class. Items classed [inAppDigital] (digital features,
/// content or subscriptions unlocked inside the app) must not be sold via an
/// external checkout from inside the app; they are blocked until an approved
/// in-app purchase flow exists. The backend should send `paymentPolicy` for
/// every item; the per-type defaults below are a stop-gap only.
enum PaymentPolicy {
  /// Physical goods (NFC cards, printed material).
  physical,

  /// In-person or business service (setup, design, consulting).
  inPersonService,

  /// Digital service consumed outside the app (website, ads management).
  externalDigitalService,

  /// Digital feature/content/subscription unlocked inside the app.
  inAppDigital;

  bool get blocksCheckout => this == PaymentPolicy.inAppDigital;

  static PaymentPolicy? tryParse(Object? v) => switch (wireKey(str(v))) {
        'physical' || 'physical_goods' || 'physical_good' =>
          PaymentPolicy.physical,
        'in_person_service' || 'business_service' || 'in_person' ||
        'service' =>
          PaymentPolicy.inPersonService,
        'external_digital_service' || 'external_digital' ||
        'digital_service' =>
          PaymentPolicy.externalDigitalService,
        'in_app_digital' || 'digital_feature' || 'in_app' ||
        'digital_content' =>
          PaymentPolicy.inAppDigital,
        _ => null,
      };

  /// Stop-gap default when the server sends no classification.
  static PaymentPolicy defaultFor(CatalogItemType type) => switch (type) {
        CatalogItemType.product => PaymentPolicy.physical,
        CatalogItemType.service => PaymentPolicy.inPersonService,
        // TODO(policy): seat plans are org-management entitlements bought on
        // the web as well; confirm classification before store release.
        CatalogItemType.plan => PaymentPolicy.externalDigitalService,
        CatalogItemType.unknown => PaymentPolicy.externalDigitalService,
      };
}

class CatalogCategory {
  const CatalogCategory({
    required this.id,
    required this.name,
    this.slug,
    this.type,
  });

  final String id;
  final String name;
  final String? slug;

  /// Which section the category belongs to, when the server scopes it.
  final CatalogItemType? type;

  /// Value sent as the `category` filter.
  String get filterValue => slug ?? id;

  factory CatalogCategory.fromJson(Object? raw) {
    final j = asJson(raw);
    final type = str(j['type']);
    return CatalogCategory(
      id: idOf(j).isEmpty ? strOr(j['slug']) : idOf(j),
      name: strOr(j['name'] ?? j['title'], 'Category'),
      slug: str(j['slug']),
      type: type == null ? null : CatalogItemType.parse(type),
    );
  }
}

class CatalogVariant {
  const CatalogVariant({
    required this.id,
    required this.name,
    this.sku,
    this.price,
    this.available = true,
  });

  final String id;
  final String name;
  final String? sku;

  /// Server price reference for display only.
  final Money? price;
  final bool available;

  factory CatalogVariant.fromJson(Object? raw, {String? currency}) {
    final j = asJson(raw);
    return CatalogVariant(
      id: idOf(j).isEmpty ? strOr(j['sku']) : idOf(j),
      name: strOr(j['name'] ?? j['title'] ?? j['label'], 'Option'),
      sku: str(j['sku']),
      price: Money.firstField(j, const ['price', 'priceReference', 'amount'],
          currency: currency),
      available: boolOrNull(j['available'] ?? j['inStock'] ?? j['active']) ??
          !_isOutOfStock(j['inventoryStatus'] ?? j['status']),
    );
  }
}

class CatalogAddOn {
  const CatalogAddOn({
    required this.id,
    required this.title,
    this.description,
    this.price,
  });

  final String id;
  final String title;
  final String? description;
  final Money? price;

  factory CatalogAddOn.fromJson(Object? raw, {String? currency}) {
    final j = asJson(raw);
    return CatalogAddOn(
      id: idOf(j),
      title: strOr(j['title'] ?? j['name'], 'Add-on'),
      description: str(j['description']),
      price: Money.firstField(j, const ['price', 'priceReference', 'amount'],
          currency: currency),
    );
  }
}

class FaqEntry {
  const FaqEntry(this.question, this.answer);
  final String question;
  final String answer;

  static FaqEntry? tryParse(Object? raw) {
    final j = asJson(raw);
    final q = str(j['question'] ?? j['q'] ?? j['title']);
    final a = str(j['answer'] ?? j['a'] ?? j['body']);
    return q == null || a == null ? null : FaqEntry(q, a);
  }
}

bool _isOutOfStock(Object? v) {
  final k = wireKey(str(v));
  return k == 'out_of_stock' || k == 'unavailable' || k == 'sold_out';
}

/// Images may be `['https://…']` or `[{url: …}]` or `media: [{type, url}]`.
List<String> _images(Json j) {
  final out = <String>[];
  for (final key in const ['images', 'media', 'gallery']) {
    final v = j[key];
    if (v is! List) continue;
    for (final e in v) {
      final url = e is String
          ? e
          : str(asJson(e)['url'] ?? asJson(e)['src'] ?? asJson(e)['secureUrl']);
      if (url != null && Validators.isSafeWebUrl(url)) out.add(url);
    }
  }
  for (final key in const ['image', 'imageUrl', 'thumbnail', 'icon']) {
    final url = str(j[key]);
    if (url != null && Validators.isSafeWebUrl(url) && !out.contains(url)) {
      out.add(url);
    }
  }
  return out;
}

List<String> _textList(Object? v) {
  if (v is List) {
    return v
        .map((e) => e is Map
            ? str(asJson(e)['title'] ?? asJson(e)['name'] ?? asJson(e)['text'])
            : str(e))
        .whereType<String>()
        .toList(growable: false);
  }
  return const [];
}

/// A service or product from `GET /catalog/services|products` and
/// `GET /catalog/:type/:id`.
class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.type,
    required this.title,
    this.slug,
    this.summary,
    this.description,
    this.images = const [],
    this.price,
    this.priceLabel,
    this.billingPeriod,
    this.categoryId,
    this.categoryName,
    this.benefits = const [],
    this.features = const [],
    this.variants = const [],
    this.addOns = const [],
    this.faq = const [],
    this.eligibilityNotes = const [],
    this.supportEmail,
    this.supportPhone,
    this.active = true,
    this.inStock = true,
    this.contactOnly = false,
    this.paymentPolicy = PaymentPolicy.externalDigitalService,
    this.policyDeclared = false,
    this.maxQuantity,
  });

  final String id;
  final CatalogItemType type;
  final String title;
  final String? slug;
  final String? summary;
  final String? description;
  final List<String> images;

  /// Server price reference — display only, never used for totals.
  final Money? price;

  /// Optional server-formatted label such as "From ₹4,999".
  final String? priceLabel;
  final String? billingPeriod;
  final String? categoryId;
  final String? categoryName;
  final List<String> benefits;
  final List<String> features;
  final List<CatalogVariant> variants;
  final List<CatalogAddOn> addOns;
  final List<FaqEntry> faq;
  final List<String> eligibilityNotes;
  final String? supportEmail;
  final String? supportPhone;
  final bool active;
  final bool inStock;

  /// No public price: the buyer must contact sales.
  final bool contactOnly;
  final PaymentPolicy paymentPolicy;

  /// False when [paymentPolicy] is the per-type stop-gap default.
  final bool policyDeclared;
  final int? maxQuantity;

  bool get purchasable =>
      active && inStock && !contactOnly && !paymentPolicy.blocksCheckout;

  factory CatalogItem.fromJson(Object? raw, {CatalogItemType? type}) {
    var j = asJson(raw);
    for (final k in const ['item', 'service', 'product']) {
      if (j[k] is Map) j = {...j, ...asJson(j[k])};
    }
    final resolvedType = type != null && type != CatalogItemType.unknown
        ? type
        : CatalogItemType.parse(j['type'] ?? j['kind']);
    final currency = str(j['currency']);
    final price = Money.firstField(
      j,
      const ['price', 'priceReference', 'basePrice', 'amount'],
      currency: currency,
    );
    final category = j['category'];
    final declared = PaymentPolicy.tryParse(
      j['paymentPolicy'] ?? j['paymentCategory'] ?? j['purchaseCategory'],
    );
    final support = asJson(j['support']);
    final status = wireKey(str(j['status']));
    final eligibility = j['eligibility'] ?? j['eligibilityNotes'] ??
        j['purchaseRules'];
    return CatalogItem(
      id: idOf(j),
      type: resolvedType,
      title: strOr(j['title'] ?? j['name'], 'Untitled'),
      slug: str(j['slug']),
      summary: str(j['summary'] ?? j['shortDescription'] ?? j['tagline']),
      description: str(j['description']),
      images: _images(j),
      price: price,
      priceLabel: str(j['priceLabel'] ?? j['displayPrice']),
      billingPeriod: str(j['billingPeriod'] ?? j['interval']),
      categoryId: category is Map ? idOf(asJson(category)) : str(category),
      categoryName:
          category is Map ? str(asJson(category)['name']) : str(j['categoryName']),
      benefits: _textList(j['benefits']),
      features: _textList(j['features'] ?? j['inclusions']),
      variants: asJsonList(j['variants'])
          .map((v) => CatalogVariant.fromJson(v, currency: currency))
          .where((v) => v.id.isNotEmpty)
          .toList(growable: false),
      addOns: asJsonList(j['addOns'] ?? j['addons'])
          .map((a) => CatalogAddOn.fromJson(a, currency: currency))
          .where((a) => a.id.isNotEmpty)
          .toList(growable: false),
      faq: (j['faq'] is List ? j['faq'] as List : const [])
          .map(FaqEntry.tryParse)
          .whereType<FaqEntry>()
          .toList(growable: false),
      eligibilityNotes:
          eligibility is String ? [eligibility] : _textList(eligibility),
      supportEmail: str(support['email'] ?? j['supportEmail']),
      supportPhone: str(support['phone'] ?? j['supportPhone']),
      active: boolOrNull(j['active'] ?? j['isActive']) ??
          !(status == 'inactive' || status == 'archived' || status == 'draft'),
      inStock: boolOrNull(j['inStock'] ?? j['available']) ??
          !_isOutOfStock(j['inventoryStatus'] ?? asJson(j['inventory'])['status']),
      contactOnly: boolOrNull(j['contactOnly'] ?? j['contactUs']) ??
          (price == null && str(j['priceLabel']) == null),
      paymentPolicy: declared ?? PaymentPolicy.defaultFor(resolvedType),
      policyDeclared: declared != null,
      maxQuantity: intOrNull(j['maxQuantity']),
    );
  }

  /// Shapes a [Plan] like a catalogue item so the shop can list it.
  factory CatalogItem.fromPlan(Plan p) => CatalogItem(
        id: p.id,
        type: CatalogItemType.plan,
        title: p.name,
        summary: p.description,
        price: p.price,
        billingPeriod: p.billingPeriod,
        features: p.features,
        active: p.active,
        contactOnly: p.price == null,
        paymentPolicy: p.paymentPolicy,
        policyDeclared: p.policyDeclared,
      );
}

/// Subscription plan from `GET /catalog/plans` (or `plans` in billing).
class Plan {
  const Plan({
    required this.id,
    required this.name,
    this.version,
    this.billingPeriod,
    this.price,
    this.priceLabel,
    this.description,
    this.features = const [],
    this.limits = const {},
    this.active = true,
    this.recommended = false,
    this.minQuantity = 1,
    this.maxQuantity,
    this.paymentPolicy = PaymentPolicy.externalDigitalService,
    this.policyDeclared = false,
  });

  final String id;
  final String name;
  final String? version;
  final String? billingPeriod;

  /// Server price reference (usually per seat per period) — display only.
  final Money? price;
  final String? priceLabel;
  final String? description;
  final List<String> features;
  final Map<String, String> limits;
  final bool active;
  final bool recommended;
  final int minQuantity;
  final int? maxQuantity;
  final PaymentPolicy paymentPolicy;
  final bool policyDeclared;

  factory Plan.fromJson(Object? raw) {
    final j = asJson(raw);
    final currency = str(j['currency']);
    final limits = <String, String>{};
    asJson(j['limits']).forEach((k, v) {
      final s = str(v);
      if (s != null) limits[k] = s;
    });
    final declared = PaymentPolicy.tryParse(j['paymentPolicy']);
    return Plan(
      id: idOf(j).isEmpty ? strOr(j['planId']) : idOf(j),
      name: strOr(j['name'] ?? j['title'], 'Plan'),
      version: str(j['version'] ?? j['planVersion']),
      billingPeriod: str(j['billingPeriod'] ?? j['interval']),
      price: Money.firstField(
        j,
        const ['price', 'pricePerSeat', 'seatPrice', 'amount'],
        currency: currency,
      ),
      priceLabel: str(j['priceLabel'] ?? j['displayPrice']),
      description: str(j['description']),
      features: _textList(j['features']),
      limits: limits,
      active: boolOr(j['active'] ?? j['isActive'], true),
      recommended: boolOr(j['recommended'] ?? j['popular']),
      minQuantity: intOr(j['minQuantity'], 1).clamp(1, 1 << 20),
      maxQuantity: intOrNull(j['maxQuantity']),
      paymentPolicy: declared ?? PaymentPolicy.defaultFor(CatalogItemType.plan),
      policyDeclared: declared != null,
    );
  }
}
