import 'package:bizzvot/core/auth/session_controller.dart';
import 'package:bizzvot/core/config/app_config.dart';
import 'package:bizzvot/features/cart_checkout/data/address_store.dart';
import 'package:bizzvot/features/catalog/data/commerce_runtime.dart';
import 'package:bizzvot/features/catalog/data/link_launcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fake_api.dart';

/// Records launches instead of opening the platform browser.
class FakeLinkLauncher extends LinkLauncher {
  FakeLinkLauncher({this.result = true});

  final bool result;
  final opened = <String>[];
  final shared = <String>[];

  @override
  Future<bool> openCheckout(String? url) async {
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    opened.add(url!);
    return result;
  }

  @override
  Future<bool> openDocument(String? url) => openCheckout(url);

  @override
  Future<bool> openWeb(String? url) async {
    if (url == null) return false;
    opened.add(url);
    return result;
  }

  @override
  Future<bool> email(String address, {String? subject}) async {
    opened.add('mailto:$address');
    return result;
  }

  @override
  Future<bool> call(String phone) async {
    opened.add('tel:$phone');
    return result;
  }

  @override
  Future<void> shareText(String text, {String? subject}) async => shared.add(text);
}

/// Captures request headers sent through [FakeApi].
List<Map<String, dynamic>> captureHeaders(FakeApi fake) {
  final headers = <Map<String, dynamic>>[];
  fake.dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (o, h) {
        headers.add(Map.of(o.headers));
        h.next(o);
      },
    ),
  );
  return headers;
}

/// Deterministic idempotency keys: key-1, key-2 …
class SequentialKeys {
  int _n = 0;
  String call() => 'key-${++_n}';
}

/// Base overrides for commerce tests: signed-in session, default config,
/// instant polling, memory address store and fake launcher.
List<Override> baseOverrides({
  FakeLinkLauncher? launcher,
  AppConfig config = AppConfig.defaults,
  String Function()? keys,
  AddressStore? addresses,
}) => [
  sessionKeyProvider.overrideWithValue('user-1'),
  currentConfigProvider.overrideWithValue(config),
  linkLauncherProvider.overrideWithValue(launcher ?? FakeLinkLauncher()),
  pollSleepProvider.overrideWithValue((_) async {}),
  addressStoreProvider.overrideWithValue(addresses ?? MemoryAddressStore()),
  if (keys != null) idempotencyKeyFactoryProvider.overrideWithValue(keys),
];

ProviderContainer makeContainer(List<Override> overrides) => ProviderContainer(
  retry: (_, _) => null,
  overrides: overrides,
);

/// Pumps [child] inside a router whose unknown locations render
/// `route:<location>`, so navigation can be asserted.
Widget harness(Widget child, {List<Override> overrides = const []}) {
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => child)],
    errorBuilder: (_, s) => Scaffold(body: Text('route:${s.uri}')),
  );
  return ProviderScope(
    retry: (_, _) => null,
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Pumps frames until [finder] matches or [maxPumps] is reached (avoids
/// pumpAndSettle hanging on skeleton/progress animations).
Future<void> pumpFor(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// Shared fixtures — physical NFC products confirmed by the owner. Prices are
// server data in these fixtures only; the app never hard-codes them.
const nfcProducts = [
  {
    '_id': 'p-stand',
    'title': 'Google Review Stand (NFC)',
    'slug': 'google-review-stand-nfc',
    'price': {'amount': '499.00', 'currency': 'INR'},
    'paymentPolicy': 'physical',
    'requiresShipping': true,
    'personalization': {'nfcTarget': 'review', 'logo': true},
  },
  {
    '_id': 'p-review-card',
    'title': 'Google Review Card (NFC)',
    'slug': 'google-review-card-nfc',
    'price': {'amount': '350.00', 'currency': 'INR'},
    'paymentPolicy': 'physical',
    'requiresShipping': true,
    'personalization': {'nfcTarget': 'review', 'logo': true},
  },
  {
    '_id': 'p-staff-id',
    'title': 'Staff ID Card (card only)',
    'slug': 'staff-id-card',
    'price': {'amount': '350.00', 'currency': 'INR'},
    'paymentPolicy': 'physical',
    'requiresShipping': true,
    'personalization': {
      'nfcTarget': 'card',
      'perUnit': true,
      'printName': true,
      'printDesignation': true,
      'logo': true,
    },
  },
  {
    '_id': 'p-business',
    'title': 'Business Digital + Physical NFC Card',
    'slug': 'business-nfc-card',
    'price': {'amount': '999.00', 'currency': 'INR'},
    'paymentPolicy': 'physical',
    'requiresShipping': true,
    'personalization': {'nfcTarget': 'card', 'printName': true, 'printDesignation': true},
  },
];
