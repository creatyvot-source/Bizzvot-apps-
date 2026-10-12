import 'package:bizzvot/core/api/endpoints.dart';
import 'package:bizzvot/core/config/app_config.dart';
import 'package:bizzvot/core/providers.dart';
import 'package:bizzvot/features/catalog/data/catalog_repository.dart';
import 'package:bizzvot/features/catalog/presentation/shop_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import 'commerce_test_utils.dart';

void main() {
  testWidgets('renders 2-option header (Products vs Services), promo banner, and 2-column grid', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = FakeApi()
      ..on(
        'GET',
        Endpoints.catalogProducts,
        FakeResponse.ok({'items': CatalogRepository.dummyProducts, 'page': 1, 'hasMore': false}),
      )
      ..on(
        'GET',
        Endpoints.catalogServices,
        FakeResponse.ok({'items': CatalogRepository.dummyServices, 'page': 1, 'hasMore': false}),
      );

    final overrides = <Override>[
      ...baseOverrides(config: AppConfig.defaults),
      apiClientProvider.overrideWithValue(fake.client),
    ];

    await tester.pumpWidget(harness(const ShopHomeScreen(), overrides: overrides));
    await pumpFor(tester, frames: 10);

    // Verify 2 header options in TabBar
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Services & Enquiry'), findsOneWidget);

    // Verify promotional banner based on poster
    expect(find.text('30% COMMISSION'), findsWidgets);
    expect(find.text('ONE CARD.\nMORE BUSINESS.'), findsOneWidget);

    // Verify 2-column grid products
    expect(find.text('Google Review Card — Tap & Review PVC'), findsWidgets);
    expect(find.text('Google Review Stand — Countertop Acrylic'), findsWidgets);
    expect(find.text('Business Digital Card — Smart NFC Profile'), findsWidgets);

    // Verify Add to Cart button presence
    expect(find.text('Add to Cart'), findsWidgets);
  });

  testWidgets('switching to Services tab displays WhatsApp enquiry and 30% reseller program', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = FakeApi()
      ..on(
        'GET',
        Endpoints.catalogProducts,
        FakeResponse.ok({'items': CatalogRepository.dummyProducts, 'page': 1, 'hasMore': false}),
      )
      ..on(
        'GET',
        Endpoints.catalogServices,
        FakeResponse.ok({'items': CatalogRepository.dummyServices, 'page': 1, 'hasMore': false}),
      );

    final overrides = <Override>[
      ...baseOverrides(config: AppConfig.defaults),
      apiClientProvider.overrideWithValue(fake.client),
    ];

    await tester.pumpWidget(harness(const ShopHomeScreen(), overrides: overrides));
    await pumpFor(tester, frames: 10);

    // Tap 'Services & Enquiry' tab
    await tester.tap(find.text('Services & Enquiry'));
    await pumpFor(tester, frames: 10);

    // Verify Reseller banner and WhatsApp buttons
    expect(find.text('Become a BizzVcard Reseller'), findsOneWidget);
    expect(find.text('Join via WhatsApp (+91 89215 04090)'), findsOneWidget);
    expect(find.text('Enquire on WhatsApp (+91 89215 04090)'), findsWidgets);
  });
}
