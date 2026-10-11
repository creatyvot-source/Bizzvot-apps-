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
      // The backend requires editCard for every staff PATCH.
      expect(
        CardEditSection.forStaff(const StaffPermissions(manageLinks: true)),
        isEmpty,
      );
      expect(
        CardEditSection.forStaff(
          const StaffPermissions(editCard: true, manageLinks: true),
        ),
        contains(CardEditSection.links),
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
    test('merge keeps known server order, drops unknown, appends defaults', () {
      final merged = DisplaySections.merge(['socials', 'gallery', 'socials']);
      expect(merged, ['socials', 'bio', 'contacts', 'customLinks']);
    });

    test('sections are visible unless toggled off', () {
      expect(DisplaySections.isVisible({}, 'showReviews'), isTrue);
      expect(
        DisplaySections.isVisible({'showReviews': false}, 'showReviews'),
        isFalse,
      );
    });
  });

  group('CardWire', () {
    test('decodes backend names', () {
      final c = CardModel.fromJson({
        '_id': 'x',
        'slug': 's',
        'title': 'T',
        'companyName': 'Acme',
        'photo': 'https://cdn/p.png',
        'theme': {
          'templateId': 'modern_dark',
          'primaryColor': '#111111',
          'layout': 'stack',
          'sectionOrder': ['socials', 'bio'],
        },
        'displayOptions': {'showBio': false},
        'socialLinks': [
          {'platform': 'linkedin', 'url': 'https://linkedin.com/in/t'},
        ],
        'customLinks': [
          {'label': 'Menu', 'url': 'https://x.com/menu', 'icon': 'menu'},
        ],
        'qrCodeUrl': 'data:image/png;base64,AAAA',
      });
      expect(c.company, 'Acme');
      expect(c.profilePhoto, 'https://cdn/p.png');
      expect(c.template, CardTemplate.modernDark);
      expect(c.brandColor, '#111111');
      expect(c.themeLayout, 'stack');
      expect(c.sectionOrder, ['socials', 'bio']);
      expect(c.displayToggles, {'showBio': false});
      expect(c.socialLinks.single.type, 'linkedin');
      expect(c.customLinks.single.icon, 'menu');
      expect(c.qrCodeUrl, startsWith('data:'));
    });

    test('still decodes legacy names', () {
      final c = CardModel.fromJson({
        'id': 'x',
        'company': 'Old',
        'profilePhoto': 'https://p',
        'template': 'minimal',
        'brandColor': '#222222',
      });
      expect(c.company, 'Old');
      expect(c.profilePhoto, 'https://p');
      expect(c.brandColor, '#222222');
    });

    test('encodes renamed fields, theme and displayOptions wholesale', () {
      final edited = original.copyWith(
        company: 'NewCo',
        profilePhoto: 'https://cdn/new.png',
        brandColor: '#00AA00',
        displayToggles: {'showBio': false},
      );
      final patch = buildCardPatch(
        original,
        edited,
        CardEditSection.ownerSections,
      );
      final body = CardWire.encodePatch(patch, edited);
      expect(body['companyName'], 'NewCo');
      expect(body['photo'], 'https://cdn/new.png');
      expect(body['theme'], {
        'templateId': 'corporate',
        'primaryColor': '#00AA00',
        'sectionOrder': <String>[],
      });
      expect(body['displayOptions'], {
        'showBio': false,
        'showSocials': true,
        'showAddress': true,
        'showWhatsapp': true,
        'showCustomLinks': true,
        'showReviews': true,
      });
      expect(body.keys, isNot(contains('company')));
      expect(body.keys, isNot(contains('profilePhoto')));
    });

    test('links use platform; custom links always carry a label', () {
      final edited = original.copyWith(
        socialLinks: const [CardLink(type: 'x', url: 'https://x.com/a', label: 'ignored')],
        customLinks: const [CardLink(type: 'custom', url: 'https://shop.example.com/p')],
      );
      final body = CardWire.encodePatch(
        {'socialLinks': [], 'customLinks': []},
        edited,
      );
      expect(body['socialLinks'], [
        {'platform': 'x', 'url': 'https://x.com/a'},
      ]);
      expect(body['customLinks'], [
        {'label': 'shop.example.com', 'url': 'https://shop.example.com/p'},
      ]);
    });

    test('never sends title:null, unsupported fields, or staff status', () {
      final body = CardWire.encodePatch(
        {
          'title': null,
          'bloodGroup': 'A+',
          'visibility': 'private',
          'gallery': [],
          'companyPhone': '1',
          'googleReviewUrl': 'https://g',
          'status': 'active',
          'designation': null,
        },
        original,
        staff: true,
      );
      expect(body, {'designation': null});
    });

    test('flag-enabled fields pass through', () {
      final body = CardWire.encodePatch(
        {'visibility': 'private'},
        original,
        enabled: {'visibility'},
      );
      expect(body, {'visibility': 'private'});
    });

    test('unsupported templates are not written', () {
      final edited = original.copyWith(template: CardTemplate.reviewCard);
      expect(CardWire.themeOf(edited).containsKey('templateId'), isFalse);
      expect(CardTemplate.reviewCard.isBackendSupported, isFalse);
      expect(CardTemplate.modernDark.isBackendSupported, isTrue);
    });

    test('create body', () {
      expect(CardWire.encodeCreate(title: ' A ', designation: ' '), {'title': 'A'});
    });
  });
}
