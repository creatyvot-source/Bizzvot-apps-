import 'package:bizzvot/core/auth/auth_user.dart';
import 'package:bizzvot/features/cards/presentation/card_detail_screen.dart';
import 'package:bizzvot/features/cards/presentation/card_editor_screen.dart';
import 'package:bizzvot/features/cards/presentation/card_share_screen.dart';
import 'package:bizzvot/features/cards/presentation/cards_list_screen.dart';
import 'package:bizzvot/features/cards/presentation/my_card_screen.dart';
import 'package:bizzvot/features/directory_visibility/data/directory_visibility_repository.dart';
import 'package:bizzvot/features/directory_visibility/presentation/directory_visibility_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';
import 'cards_test_harness.dart';

/// Every main screen must lay out at a 360dp phone width with 200% text
/// (an overflow fails the test).
void main() {
  const phone = Size(360, 2400);
  final card = cardJson(
    status: 'disabled',
    disabledByBilling: true,
    extra: {
      'bio': 'Helping teams grow with thoughtful, long-term partnerships across the region.',
      'website': 'https://example.com',
      'whatsapp': '+91 90000 00000',
      'address': '12 MG Road, Bengaluru',
      'socialLinks': [
        {'type': 'linkedin', 'url': 'https://linkedin.com/in/asha'},
      ],
      'template': 'review_card',
      'averageRating': 4.6,
      'reviewCount': 12,
    },
  );

  BinaryFakeApi api() => BinaryFakeApi()
    ..on('GET', '/organization/cards', FakeResponse.ok([card]))
    ..on('GET', '/organization/cards/c1', FakeResponse.ok(card))
    ..on('GET', '/staff/card', FakeResponse.ok(card))
    ..on(
      'GET',
      '/organization/profile',
      FakeResponse.ok({'_id': 'o', 'name': 'Acme', 'slug': 'acme'}),
    )
    ..onBytes('GET', '/cards/c1/qrcode', tinyPng);

  final screens = <String, (Widget, AuthUser)>{
    'list': (const CardsListScreen(), ownerUser),
    'detail': (const CardDetailScreen(cardId: 'c1'), ownerUser),
    'editor': (const CardEditorScreen(cardId: 'c1'), ownerUser),
    'share': (const CardShareScreen(cardId: 'c1'), ownerUser),
    'my card': (
      const MyCardScreen(),
      staffUser(
        permissions: const StaffPermissions(editCard: true, manageLinks: true),
      ),
    ),
    'directory': (const DirectoryVisibilityScreen(), ownerUser),
  };

  for (final MapEntry(key: name, value: (screen, user)) in screens.entries) {
    testWidgets('$name survives 200% text at phone width', (tester) async {
      final fake = api();
      await pumpScreen(
        tester,
        screen,
        api: fake,
        user: user,
        size: phone,
        textScale: 2,
        extra: [
          directoryVisibilityRepositoryProvider.overrideWithValue(
            DirectoryVisibilityRepository(fake.client),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
    });
  }
}
