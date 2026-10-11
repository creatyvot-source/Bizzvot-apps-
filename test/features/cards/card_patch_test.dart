import 'package:bizzvot/core/auth/auth_user.dart';
import 'package:bizzvot/features/cards/domain/card_edit_sections.dart';
import 'package:bizzvot/features/cards/domain/display_sections.dart';
import 'package:bizzvot/shared/models/card.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cards_test_harness.dart';

void main() {
  final original = CardModel.fromJson(cardJson());

  group('buildCardPatch', () {
    test('no changes → empty patch', () {
      expect(
        buildCardPatch(original, original, CardEditSection.ownerSections),
        isEmpty,
      );
    });

    test('only changed fields are sent', () {
      final edited = original.copyWith(
        title: 'Asha R.',
        visibility: CardVisibility.private,
      );
      expect(buildCardPatch(original, edited, CardEditSection.ownerSections), {
        'title': 'Asha R.',
        'visibility': 'private',
      });
    });

    test('cleared fields are sent as null; whitespace is trimmed', () {
      final edited = original.copyWith(
        company: '  Acme  ',
        clear: {'designation'},
      );
      expect(buildCardPatch(original, edited, CardEditSection.ownerSections), {
        'designation': null,
      });
    });

    test('fields outside allowed sections are never sent', () {
      final edited = original.copyWith(
        title: 'Changed',
        socialLinks: const [
          CardLink(type: 'linkedin', url: 'https://linkedin.com/in/asha'),
        ],
      );
      final patch = buildCardPatch(original, edited, {CardEditSection.links});
      expect(patch.keys, ['socialLinks']);
    });
  });

  group('staff sections', () {
    test('editCard grants content sections only', () {
      final s = CardEditSection.forStaff(
        const StaffPermissions(editCard: true),
      );
      expect(
        s,
        containsAll([
          CardEditSection.identity,
          CardEditSection.media,
          CardEditSection.appearance,
        ]),
      );
      expect(s, isNot(contains(CardEditSection.links)));
      expect(s, isNot(contains(CardEditSection.privateDetails)));
      expect(s, isNot(contains(CardEditSection.visibility)));
    });

    test('manageLinks grants links only; none grants nothing', () {
      expect(
        CardEditSection.forStaff(const StaffPermissions(manageLinks: true)),
        {CardEditSection.links},
      );
      expect(CardEditSection.forStaff(StaffPermissions.none), isEmpty);
    });
  });

  test(
    'CardModel.copyWith(clear:) resets nullable fields and keeps the rest',
    () {
      final c = original.copyWith(clear: {'bloodGroup', 'title'});
      expect(c.bloodGroup, isNull);
      expect(c.title, isNull);
      expect(c.designation, 'Sales Lead');
      expect(c.fatherName, 'Ravi Rao');
      expect(original.copyWith(title: 'X').title, 'X');
    },
  );

  group('DisplaySections', () {
    test('merge keeps server order, dedupes and appends defaults', () {
      final merged = DisplaySections.merge([
        'gallery',
        'custom_block',
        'gallery',
      ]);
      expect(merged.take(2), ['gallery', 'custom_block']);
      expect(merged.toSet(), containsAll(DisplaySections.defaults));
      expect(merged.where((k) => k == 'gallery'), hasLength(1));
    });

    test('sections are visible unless toggled off', () {
      expect(DisplaySections.isVisible({}, 'reviews'), isTrue);
      expect(DisplaySections.isVisible({'reviews': false}, 'reviews'), isFalse);
    });
  });
}
