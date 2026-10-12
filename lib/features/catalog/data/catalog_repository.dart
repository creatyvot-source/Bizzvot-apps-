import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utilities/json.dart';
import '../../../shared/models/paged.dart';
import '../domain/catalog_models.dart';
import '../domain/money.dart';

/// Filter for catalogue listings. Records compare by value, so this is a
/// stable provider family key.
typedef CatalogQuery = ({
  CatalogItemType type,
  String? category,
  String? search,
});

/// PROPOSED commerce catalogue endpoints (plan §12.5).
class CatalogRepository {
  CatalogRepository(this._api);

  final ApiClient _api;

  static const pageSize = 20;

  static const dummyProducts = [
    CatalogItem(
      id: 'prod-review-card',
      type: CatalogItemType.product,
      title: 'Google Review Card — Tap & Review PVC',
      slug: 'google-review-card',
      summary: 'Simple card to get more Google reviews instantly via NFC & QR.',
      description: 'Ultra-thin ISO 7810 PVC smart card with high-speed NTAG213 NFC chip. Hand it to customers or tap their phone after service to capture 5-star positive reviews instantly on Google Maps.',
      price: Money(35000, 'INR'),
      priceLabel: '₹350 / card',
      categoryId: 'cards',
      requiresShipping: true,
      paymentPolicy: PaymentPolicy.physical,
      variants: [
        CatalogVariant(id: 'card-1', name: '1 Card (Single)', price: Money(35000, 'INR')),
        CatalogVariant(id: 'card-3', name: '3 Cards Combo', price: Money(89900, 'INR')),
        CatalogVariant(id: 'card-5', name: '5 Cards Combo', price: Money(119900, 'INR')),
      ],
      features: [
        'NTAG213 NFC chip embedded',
        'Dynamic QR Code for non-NFC phones',
        'Direct link to your Google Review page',
        'No apps required for customers',
        '+ 18% GST & express courier extra',
      ],
      images: [
        'https://images.unsplash.com/photo-1589758438368-0ad531db3366?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1563986768609-322da13575f3?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1559526324-4b87b5e36e44?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=800&auto=format&fit=crop&q=80',
      ],
    ),
    CatalogItem(
      id: 'prod-review-stand',
      type: CatalogItemType.product,
      title: 'Google Review Stand — Countertop Acrylic',
      slug: 'google-review-stand',
      summary: 'Countertop stand design for maximum visibility at your business reception or checkout.',
      description: 'Durable clear acrylic countertop stand designed for reception counters, dining tables, and checkout registers. Customers simply tap with any phone to immediately open your Google Review page.',
      price: Money(49900, 'INR'),
      priceLabel: '₹499 with stand',
      categoryId: 'stands',
      requiresShipping: true,
      paymentPolicy: PaymentPolicy.physical,
      variants: [
        CatalogVariant(id: 'stand-1', name: '1 Stand (Single)', price: Money(49900, 'INR')),
        CatalogVariant(id: 'stand-3', name: '3 Stands Combo', price: Money(109900, 'INR')),
        CatalogVariant(id: 'stand-5', name: '5 Stands Combo', price: Money(169900, 'INR')),
      ],
      features: [
        'High-grade acrylic countertop stand',
        'Dual NFC tap + prominent QR code',
        'Zero battery or power needed',
        '+ 18% GST & express courier extra',
        '30% commission eligible for resellers',
      ],
      images: [
        'https://images.unsplash.com/photo-1556742049-0a67c5574f73?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1522071820081-009f0129c71c?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1556740758-90de374c12ad?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800&auto=format&fit=crop&q=80',
      ],
    ),
    CatalogItem(
      id: 'prod-business-card',
      type: CatalogItemType.product,
      title: 'Business Digital Card — Smart NFC Profile',
      slug: 'business-digital-card',
      summary: 'Smart NFC card with your complete business profile, contacts, catalog & socials.',
      description: 'The ultimate smart business card experience. Tap to share entire organization profiles, brochures, catalogs, and instant WhatsApp chat with one tap.',
      price: Money(99900, 'INR'),
      priceLabel: '₹999 / card',
      categoryId: 'bundles',
      requiresShipping: true,
      paymentPolicy: PaymentPolicy.physical,
      variants: [
        CatalogVariant(id: 'biz-1', name: '1 Business Card', price: Money(99900, 'INR')),
        CatalogVariant(id: 'biz-3', name: '3 Cards Combo', price: Money(249900, 'INR')),
        CatalogVariant(id: 'biz-5', name: '5 Cards Combo', price: Money(399900, 'INR')),
      ],
      features: [
        'Executive matte finish NFC card',
        'Live digital profile with 1-tap contact save',
        'WhatsApp direct connect & call buttons',
        '+ 18% GST & express courier extra',
        'Editable anytime from your mobile dashboard',
      ],
      images: [
        'https://images.unsplash.com/photo-1544717305-2782549b5136?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1556742111-a301076d9d18?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1616469829941-c7200edec809?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1557804506-669a67965ba0?w=800&auto=format&fit=crop&q=80',
      ],
    ),
    CatalogItem(
      id: 'prod-badge',
      type: CatalogItemType.product,
      title: 'Staff ID Smart Card — NFC & Dynamic QR',
      slug: 'staff-id-card',
      summary: 'Dual-side thermal print smart badge with instant vCard contact download.',
      description: 'Heavy-duty 30-mil CR80 PVC identity badge with custom corporate branding, employee photo, and instant tap vCard redirect.',
      price: Money(35000, 'INR'),
      priceLabel: '₹350 / card',
      categoryId: 'badges',
      requiresShipping: true,
      paymentPolicy: PaymentPolicy.physical,
      variants: [
        CatalogVariant(id: 'badge-1', name: '1 Staff Card', price: Money(35000, 'INR')),
        CatalogVariant(id: 'badge-3', name: '3 Staff Cards', price: Money(89900, 'INR')),
        CatalogVariant(id: 'badge-5', name: '5 Staff Cards', price: Money(119900, 'INR')),
      ],
      features: [
        'Thermal card print with lanyard slot',
        'Staff management from owner portal',
        '+ 18% GST & express courier extra',
        'Direct contact share & analytics',
      ],
      images: [
        'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1507679799987-c73779587ccf?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1521737604893-d14cc237f11d?w=800&auto=format&fit=crop&q=80',
      ],
    ),
  ];

  static const dummyServices = [
    CatalogItem(
      id: 'serv-reseller',
      type: CatalogItemType.service,
      title: 'BizzVcard Reseller Program — Earn 30% Commission',
      slug: 'reseller-program',
      summary: 'Earn 30% commission on every sale. High demand Google Review & Smart NFC cards.',
      description: 'Become an official BizzVcard Reseller partner. Sell digital cards and Google review solutions to local businesses, shops, and restaurants. Get marketing posters, product images, onboarding training, and 30% margin on all orders.',
      price: Money(0, 'INR'),
      priceLabel: 'Free to Join · 30% Commission',
      categoryId: 'reseller',
      contactOnly: true,
      supportPhone: '+91 89215 04090',
      paymentPolicy: PaymentPolicy.inPersonService,
      features: [
        'High Demand Products (Digital Cards & Review Stands)',
        '30% Direct Commission on every product sold',
        'Marketing support: posters, content & product images',
        'Easy onboarding with quick & simple process',
        'Tap, connect, grow your local agency business',
      ],
      images: [
        'https://images.unsplash.com/photo-1556742049-0a67c5574f73?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1552664730-d307ca884978?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1542744173-8e7e53415bb0?w=800&auto=format&fit=crop&q=80',
      ],
    ),
    CatalogItem(
      id: 'serv-setup',
      type: CatalogItemType.service,
      title: 'Google Business Profile & Review Setup',
      slug: 'google-business-setup',
      summary: 'Place ID link generation, NFC test verification, and review campaign QR calibration.',
      description: 'Complete audit and link generation for your Google Maps listing to maximize review capture rates and eliminate review friction.',
      price: Money(49900, 'INR'),
      priceLabel: '₹499 one-time enquiry',
      categoryId: 'services',
      contactOnly: true,
      supportPhone: '+91 89215 04090',
      paymentPolicy: PaymentPolicy.inPersonService,
      features: [
        'Direct Google Place ID linking',
        'Fast 1-tap review redirect',
        'Verification support on WhatsApp',
      ],
      images: [
        'https://images.unsplash.com/photo-1572021335469-31706a17aaef?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1460925895917-afdab827c52f?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1432888498266-38ffec3eaf0a?w=800&auto=format&fit=crop&q=80',
      ],
    ),
    CatalogItem(
      id: 'serv-design',
      type: CatalogItemType.service,
      title: 'Custom Card Graphic Design & Branding',
      slug: 'custom-card-design',
      summary: 'Professional vector layout, custom typography, QR embedding, and multi-format export.',
      description: 'Our senior brand designers craft high-resolution print-ready graphics tailored to your company visual identity, color scheme, and typography guidelines.',
      price: Money(79900, 'INR'),
      priceLabel: '₹799 / design enquiry',
      categoryId: 'services',
      contactOnly: true,
      supportPhone: '+91 89215 04090',
      paymentPolicy: PaymentPolicy.inPersonService,
      features: [
        'Custom corporate design layout',
        'High-resolution CMYK print export',
        'Fast turnaround on WhatsApp',
      ],
      images: [
        'https://images.unsplash.com/photo-1600132806370-bf17e65e942f?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1558655146-d09347e92766?w=800&auto=format&fit=crop&q=80',
      ],
    ),
    CatalogItem(
      id: 'serv-bulk',
      type: CatalogItemType.service,
      title: 'Enterprise Bulk NFC Tag Provisioning',
      slug: 'enterprise-bulk-nfc',
      summary: 'Pre-encoding 50+ NFC chips with secure dynamic redirect URLs and asset tag numbering.',
      description: 'Comprehensive chip encoding and quality audit for high-volume enterprise rollouts. Includes Cloudflare edge routing and dynamic reassignment dashboard.',
      price: Money(149900, 'INR'),
      priceLabel: '₹1,499 setup enquiry',
      categoryId: 'services',
      contactOnly: true,
      supportPhone: '+91 89215 04090',
      paymentPolicy: PaymentPolicy.inPersonService,
      features: [
        'Pre-programmed NTAG213 chips',
        'Custom domain redirect setup',
        'Direct WhatsApp support: +91 89215 04090',
      ],
      images: [
        'https://images.unsplash.com/photo-1551288049-bebda4e38f71?w=800&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?w=800&auto=format&fit=crop&q=80',
      ],
    ),
  ];

  static const dummyCategories = [
    CatalogCategory(id: '', name: 'All NFC'),
    CatalogCategory(id: 'stands', name: 'Review Stands', slug: 'stands'),
    CatalogCategory(id: 'cards', name: 'Smart Cards', slug: 'cards'),
    CatalogCategory(id: 'badges', name: 'ID Badges', slug: 'badges'),
    CatalogCategory(id: 'bundles', name: 'Bundles', slug: 'bundles'),
    CatalogCategory(id: 'services', name: 'Services', slug: 'services'),
  ];

  Future<List<CatalogCategory>> categories() async {
    try {
      final list = await _api.get(
        Endpoints.catalogCategories,
        parse: (d) => Paged.parse(
          d,
          CatalogCategory.fromJson,
          listKeys: const ['categories', 'items', 'data'],
        ).items.where((c) => c.id.isNotEmpty).toList(growable: false),
      );
      return list.isEmpty ? dummyCategories : list;
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.network) {
        return dummyCategories;
      }
      rethrow;
    }
  }

  /// `GET /catalog/services|products` with `category`, `q`, `page`, `limit`.
  Future<Paged<CatalogItem>> items(CatalogQuery q, {int page = 1}) async {
    final path = switch (q.type) {
      CatalogItemType.product => Endpoints.catalogProducts,
      CatalogItemType.plan => Endpoints.catalogPlans,
      _ => Endpoints.catalogServices,
    };
    try {
      final res = await _api.get(
        path,
        query: {
          'category': q.category,
          'q': (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
          'page': page,
          'limit': pageSize,
        },
        parse: (d) => q.type == CatalogItemType.plan
            ? _plansAsItems(d)
            : Paged.parse(
                d,
                (raw) => CatalogItem.fromJson(raw, type: q.type),
                listKeys: const [
                  'items',
                  'services',
                  'products',
                  'docs',
                  'results',
                  'data',
                ],
              ),
      );
      if (res.items.isNotEmpty) return res;
      return _fallbackItems(q);
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.network) {
        return _fallbackItems(q);
      }
      rethrow;
    }
  }

  Paged<CatalogItem> _fallbackItems(CatalogQuery q) {
    final source = q.type == CatalogItemType.product ? dummyProducts : dummyServices;
    var filtered = source;
    if (q.category != null && q.category!.isNotEmpty) {
      filtered = filtered.where((item) => item.categoryId == q.category).toList();
    }
    if (q.search != null && q.search!.trim().isNotEmpty) {
      final s = q.search!.trim().toLowerCase();
      filtered = filtered
          .where((item) =>
              item.title.toLowerCase().contains(s) ||
              (item.summary?.toLowerCase().contains(s) ?? false))
          .toList();
    }
    return Paged<CatalogItem>(
      items: filtered,
      total: filtered.length,
      page: 1,
      hasMore: false,
    );
  }

  /// `GET /catalog/plans`.
  Future<List<Plan>> plans() => _api.get(
    Endpoints.catalogPlans,
    parse: (d) => Paged.parse(
      d,
      Plan.fromJson,
      listKeys: const ['plans', 'items', 'data'],
    ).items.where((p) => p.id.isNotEmpty).toList(growable: false),
  );

  /// `GET /catalog/:type/:id`.
  Future<CatalogItem> item(CatalogItemType type, String id) async {
    try {
      return await _api.get(
        Endpoints.catalogItem(type.wire, id),
        parse: (d) {
          if (type == CatalogItemType.plan) {
            final j = asJson(d);
            final plan = Plan.fromJson(j['plan'] is Map ? j['plan'] : j);
            final base = CatalogItem.fromJson(
              j['plan'] is Map ? j['plan'] : j,
              type: CatalogItemType.plan,
            );
            return base.price == null && plan.price != null
                ? CatalogItem.fromPlan(plan)
                : base;
          }
          return CatalogItem.fromJson(d, type: type);
        },
      );
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.network) {
        final source = type == CatalogItemType.product ? dummyProducts : dummyServices;
        return source.firstWhere(
          (it) => it.id == id || it.slug == id,
          orElse: () => source.first,
        );
      }
      rethrow;
    }
  }

  static Paged<CatalogItem> _plansAsItems(Object? d) {
    final paged = Paged.parse(
      d,
      Plan.fromJson,
      listKeys: const ['plans', 'items', 'data'],
    );
    return Paged(
      items: paged.items
          .where((p) => p.id.isNotEmpty)
          .map(CatalogItem.fromPlan)
          .toList(growable: false),
      total: paged.total,
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(apiClientProvider)),
);
