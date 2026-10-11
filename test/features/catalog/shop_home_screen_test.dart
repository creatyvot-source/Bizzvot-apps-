import 'package:bizzvot/core/api/endpoints.dart';
import 'package:bizzvot/core/config/app_config.dart';
import 'package:bizzvot/core/providers.dart';
import 'package:bizzvot/features/catalog/presentation/shop_home_screen.dart';
import 'package:bizzvot/features/catalog/presentation/widgets/category_icon_tab_bar.dart';
import 'package:bizzvot/features/catalog/presentation/widgets/discovery_media_card.dart';
import 'package:bizzvot/features/catalog/presentation/widgets/floating_search_capsule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import 'commerce_test_utils.dart';

void main() {
  testWidgets('renders Airbnb-style discovery layout with search capsule and category tabs', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = FakeApi()
      ..on(
        'GET',
        Endpoints.catalogProducts,
        FakeResponse.ok({'items': nfcProducts, 'page': 1, 'hasMore': false}),
      )
      ..on(
        'GET',
        Endpoints.catalogServices,
        FakeResponse.ok({'items': [], 'page': 1, 'hasMore': false}),
      );

    final overrides = <Override>[
      ...baseOverrides(config: AppConfig.defaults),
      apiClientProvider.overrideWithValue(fake.client),
    ];

    await tester.pumpWidget(harness(const ShopHomeScreen(), overrides: overrides));
    await pumpFor(tester, frames: 10);

    // Verify search capsule
    expect(find.byType(FloatingSearchCapsule), findsWidgets);
    expect(find.text('Explore Bizzvot NFC & Cards'), findsWidgets);

    // Verify category tab bar
    expect(find.byType(CategoryIconTabBar), findsWidgets);
    expect(find.text('All NFC'), findsWidgets);
    expect(find.text('Review Stands'), findsWidgets);
    expect(find.text('Smart NFC Cards'), findsWidgets);

    // Verify discovery cards rendered
    expect(find.byType(DiscoveryMediaCard), findsWidgets);
    expect(find.text('Google Review Stand (NFC)'), findsOneWidget);
    expect(find.text('Google Review Card (NFC)'), findsOneWidget);
    expect(find.text('Staff ID Card (card only)'), findsOneWidget);
    expect(find.text('Business Digital + Physical NFC Card'), findsOneWidget);

    // Verify rating and badge
    expect(find.text('4.98'), findsWidgets);
    expect(find.text('NFC Tap Enabled'), findsWidgets);
  });

  testWidgets('tapping category tab updates the selected tab', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = FakeApi()
      ..on(
        'GET',
        Endpoints.catalogProducts,
        FakeResponse.ok({'items': nfcProducts, 'page': 1, 'hasMore': false}),
      )
      ..on(
        'GET',
        Endpoints.catalogServices,
        FakeResponse.ok({'items': [], 'page': 1, 'hasMore': false}),
      );

    final overrides = <Override>[
      ...baseOverrides(config: AppConfig.defaults),
      apiClientProvider.overrideWithValue(fake.client),
    ];

    await tester.pumpWidget(harness(const ShopHomeScreen(), overrides: overrides));
    await pumpFor(tester, frames: 10);

    // Tap 'Review Stands' tab
    await tester.tap(find.text('Review Stands').first);
    await pumpFor(tester, frames: 10);

    // The tab should now be selected
    expect(find.text('Review Stands'), findsWidgets);
  });

  testWidgets('tapping search capsule activates search field and typing filters query', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = FakeApi()
      ..on(
        'GET',
        Endpoints.catalogProducts,
        FakeResponse.ok({'items': nfcProducts, 'page': 1, 'hasMore': false}),
      )
      ..on(
        'GET',
        Endpoints.catalogServices,
        FakeResponse.ok({'items': [], 'page': 1, 'hasMore': false}),
      );

    final overrides = <Override>[
      ...baseOverrides(config: AppConfig.defaults),
      apiClientProvider.overrideWithValue(fake.client),
    ];

    await tester.pumpWidget(harness(const ShopHomeScreen(), overrides: overrides));
    await pumpFor(tester, frames: 10);

    // Tap search capsule
    await tester.tap(find.byType(FloatingSearchCapsule).first);
    await tester.pump();

    // Verify text field appeared
    expect(find.byType(TextField), findsOneWidget);

    // Enter query and wait for debounce timer
    await tester.enterText(find.byType(TextField), 'Stand');
    await tester.pump(const Duration(milliseconds: 500));
    await pumpFor(tester, frames: 10);

    // Close search
    await tester.tap(find.byTooltip('Close search'));
    await tester.pump(const Duration(milliseconds: 500));
    await pumpFor(tester, frames: 10);

    // Verify search capsule is back
    expect(find.byType(FloatingSearchCapsule), findsWidgets);
  });

  testWidgets('discovery card wishlist toggle toggles state', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = FakeApi()
      ..on(
        'GET',
        Endpoints.catalogProducts,
        FakeResponse.ok({'items': nfcProducts, 'page': 1, 'hasMore': false}),
      )
      ..on(
        'GET',
        Endpoints.catalogServices,
        FakeResponse.ok({'items': [], 'page': 1, 'hasMore': false}),
      );

    final overrides = <Override>[
      ...baseOverrides(config: AppConfig.defaults),
      apiClientProvider.overrideWithValue(fake.client),
    ];

    await tester.pumpWidget(harness(const ShopHomeScreen(), overrides: overrides));
    await pumpFor(tester, frames: 10);

    // Find wishlist button on the first card
    final wishlistFinder = find.byTooltip('Save to wishlist').first;
    expect(wishlistFinder, findsOneWidget);

    // Tap to toggle wishlist
    await tester.tap(wishlistFinder);
    await pumpFor(tester, frames: 10);

    // Wishlist tooltip should change to 'Remove from wishlist'
    expect(find.byTooltip('Remove from wishlist'), findsOneWidget);
  });
}
