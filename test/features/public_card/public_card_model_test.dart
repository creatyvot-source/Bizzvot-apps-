import 'dart:convert';

import 'package:bizzvot/features/public_card/data/external_actions.dart';
import 'package:bizzvot/features/public_card/domain/contact_links.dart';
import 'package:bizzvot/features/public_card/domain/public_card.dart';
import 'package:bizzvot/features/public_card/domain/public_directory.dart';
import 'package:bizzvot/features/public_card/domain/public_review.dart';
import 'package:bizzvot/shared/models/card.dart';
import 'package:flutter_test/flutter_test.dart';

/// A payload that (wrongly) includes private and internal fields.
Map<String, dynamic> leakyPayload() => {
  '_id': 'card-1',
  'slug': 'jane-doe',
  'title': 'Jane Doe',
  'designation': 'Head of Sales',
  'phone': '+91 98765 43210',
  'email': 'jane@acme.test',
  'bloodGroup': 'AB-NEG-SECRET',
  'fatherName': 'FATHER-SECRET',
  'motherName': 'MOTHER-SECRET',
  'privateDetails': {
    'bloodGroup': 'PD-BLOOD-SECRET',
    'fatherName': 'PD-FATHER-SECRET',
  },
  'reviewerEmail': 'REVIEWER-EMAIL-SECRET',
  'ip': '203.0.113.9',
  'internalNotes': 'INTERNAL-SECRET',
  'staffUserId': 'STAFF-ID-SECRET',
  'displayToggles': {
    'showPhone': true,
    'bloodGroup': true,
    'showFatherName': true,
  },
  'socialLinks': [
    {
      'type': 'linkedin',
      'url': 'https://linkedin.com/in/jane',
      '_id': 'LINK-ID-SECRET',
    },
  ],
  'gallery': [
    {
      'url': 'https://cdn.test/a.jpg',
      '_id': 'MEDIA-ID-SECRET',
      'uploadedBy': 'UPLOADER-SECRET',
    },
  ],
  'organization': {
    'name': 'Acme',
    'logo': 'https://cdn.test/logo.png',
    'ownerEmail': 'OWNER-SECRET',
  },
};

void main() {
  group('PublicCard privacy', () {
    test('private and internal keys in the payload are never exposed', () {
      final card = PublicCard.fromJson(leakyPayload());
      final dump = jsonEncode(card.toPublicJson());

      for (final secret in [
        'AB-NEG-SECRET',
        'FATHER-SECRET',
        'MOTHER-SECRET',
        'PD-BLOOD-SECRET',
        'PD-FATHER-SECRET',
        'REVIEWER-EMAIL-SECRET',
        '203.0.113.9',
        'INTERNAL-SECRET',
        'STAFF-ID-SECRET',
        'LINK-ID-SECRET',
        'MEDIA-ID-SECRET',
        'UPLOADER-SECRET',
        'OWNER-SECRET',
      ]) {
        expect(dump, isNot(contains(secret)), reason: '$secret leaked');
      }
      final lower = dump.toLowerCase();
      for (final key in [
        'bloodgroup',
        'fathername',
        'mothername',
        'privatedetails',
        '"ip"',
      ]) {
        expect(lower, isNot(contains(key)), reason: '$key leaked');
      }
      // Public data is still there.
      expect(card.name, 'Jane Doe');
      expect(card.phone, '+91 98765 43210');
      expect(card.organizationName, 'Acme');
      expect(card.socialLinks.single.url, 'https://linkedin.com/in/jane');
    });

    test('public reviews drop reviewer email and IP', () {
      final r = PublicReview.fromJson({
        '_id': 'r1',
        'reviewerName': 'Sam',
        'rating': 4,
        'email': 'sam@x.test',
        'reviewerEmail': 'sam@x.test',
        'ip': '198.51.100.1',
        'comment': 'Great',
        'reply': {'text': 'Thanks Sam'},
      });
      expect(r.reviewerName, 'Sam');
      expect(r.reply?.text, 'Thanks Sam');
      // The DTO has no field that could carry them; check textual output too.
      expect(
        '${r.id}${r.reviewerName}${r.comment}${r.reply?.text}',
        isNot(contains('sam@x.test')),
      );
    });

    test('only approved (or unmarked) reviews are publishable', () {
      expect(PublicReview.isPublishable({'status': 'approved'}), isTrue);
      expect(PublicReview.isPublishable({}), isTrue);
      expect(PublicReview.isPublishable({'status': 'pending'}), isFalse);
      expect(PublicReview.isPublishable({'status': 'hidden'}), isFalse);
    });
  });

  group('PublicCard parsing', () {
    test('nested {card, organization} payload, template, stats', () {
      final card = PublicCard.fromJson({
        'card': {
          'id': 'c9',
          'slug': 's',
          'name': 'Raj',
          'template': 'review_card',
          'brandColor': '#112233',
          'googleReviewLink': 'https://g.page/r/abc',
          'vcardEnabled': false,
          'averageRating': '4.5',
          'reviewCount': 12,
        },
        'organization': {'name': 'Org'},
      });
      expect(card.id, 'c9');
      expect(card.template, CardTemplate.reviewCard);
      expect(card.googleReviewUrl, 'https://g.page/r/abc');
      expect(card.vcardEnabled, isFalse);
      expect(card.canSaveContact, isFalse);
      expect(card.averageRating, 4.5);
      expect(card.reviewCount, 12);
      expect(card.organizationName, 'Org');
    });

    test('sectionOrder keeps known sections and appends the rest', () {
      final card = PublicCard.fromJson({
        'slug': 's',
        'sectionOrder': [
          'reviews',
          'socialLinks',
          'bogus',
          'gallery',
          'reviews',
        ],
      });
      expect(card.sectionOrder.take(3), [
        PublicSection.reviews,
        PublicSection.social,
        PublicSection.gallery,
      ]);
      expect(card.sectionOrder.toSet().length, PublicSection.values.length);
    });

    test('display toggles are normalised (showPhone == phone)', () {
      final card = PublicCard.fromJson({
        'slug': 's',
        'displayToggles': {
          'showPhone': false,
          'show_gallery': 'false',
          'reviews': true,
        },
      });
      expect(card.shows(['phone']), isFalse);
      expect(card.showsSection(PublicSection.gallery), isFalse);
      expect(card.showsSection(PublicSection.reviews), isTrue);
      expect(card.shows(['email']), isTrue);
    });

    test('vCard needs an id and vcardEnabled != false', () {
      expect(PublicCard.fromJson({'slug': 's'}).canSaveContact, isFalse);
      expect(
        PublicCard.fromJson({'slug': 's', '_id': 'x'}).canSaveContact,
        isTrue,
      );
    });

    test('directory parses entries and skips ones without slug', () {
      final page = PublicDirectoryPage.fromJson({
        'organization': {'name': 'Acme'},
        'people': [
          {
            'slug': 'a',
            'title': 'Ann',
            'designation': 'CEO',
            'bloodGroup': 'X',
          },
          {'title': 'No slug'},
          {
            'card': {'slug': 'b', 'name': 'Ben'},
          },
        ],
        'page': 1,
        'pages': 2,
      });
      expect(page.organizationName, 'Acme');
      expect(page.entries.map((e) => e.slug), ['a', 'b']);
      expect(page.entries.first.designation, 'CEO');
      expect(page.hasMore, isTrue);
    });

    test('submission result: approved vs pending (default)', () {
      expect(
        ReviewSubmissionResult.fromJson({'status': 'approved'}).isApproved,
        isTrue,
      );
      expect(
        ReviewSubmissionResult.fromJson({
          'review': {'status': 'approved'},
        }).isApproved,
        isTrue,
      );
      expect(
        ReviewSubmissionResult.fromJson({'status': 'pending'}).isApproved,
        isFalse,
      );
      expect(ReviewSubmissionResult.fromJson(null).isApproved, isFalse);
    });

    test('submission body omits an empty comment', () {
      expect(
        const ReviewSubmission(
          rating: 5,
          name: ' Ann ',
          comment: '  ',
        ).toJson(),
        {'reviewerName': 'Ann', 'rating': 5},
      );
    });
  });

  test('backend public DTO fields (companyName, photo, theme, displayOptions, platform)', () {
    final card = PublicCard.fromJson({
      '_id': '665f0c',
      'slug': 'raj',
      'title': 'Raj Kumar',
      'companyName': 'Acme Pvt Ltd',
      'photo': 'https://cdn.test/raj.jpg',
      'theme': {
        'templateId': 'modern_dark',
        'primaryColor': '#5B2C8A',
        'sectionOrder': ['customLinks', 'bio', 'socials', 'contacts'],
      },
      'displayOptions': {
        'showBio': false,
        'showWhatsapp': true,
        'showReviews': false,
      },
      'socialLinks': [
        {'platform': 'instagram', 'url': 'https://instagram.com/raj'},
      ],
      'customLinks': [
        {'label': 'Portfolio', 'url': 'https://raj.dev', 'icon': 'globe'},
      ],
      'vcardEnabled': true,
      'type': 'organization',
      'status': 'active',
    });
    expect(card.id, '665f0c');
    expect(card.company, 'Acme Pvt Ltd');
    expect(card.profilePhoto, 'https://cdn.test/raj.jpg');
    expect(card.template, CardTemplate.modernDark);
    expect(card.brandColor, '#5B2C8A');
    expect(card.sectionOrder.take(4), [
      PublicSection.links,
      PublicSection.about,
      PublicSection.social,
      PublicSection.contact,
    ]);
    expect(card.showsSection(PublicSection.about), isFalse);
    expect(card.showsSection(PublicSection.reviews), isFalse);
    expect(card.shows(['whatsapp']), isTrue);
    expect(card.socialLinks.single.type, 'instagram');
    expect(card.customLinks.single.label, 'Portfolio');
    expect(card.canSaveContact, isTrue);
  });

  test('templates the backend lacks fall back gracefully', () {
    expect(
      PublicCard.fromJson({
        'theme': {'templateId': 'neon_future'},
      }).template,
      CardTemplate.minimal,
    );
  });

  group('ContactLinks', () {
    test('tel keeps a leading + and strips punctuation', () {
      expect(
        ContactLinks.tel('+91 (987) 654-3210').toString(),
        'tel:+919876543210',
      );
      expect(ContactLinks.tel('ab'), isNull);
    });

    test('whatsapp builds https://wa.me/<digits>', () {
      expect(
        ContactLinks.whatsapp('+91 98765 43210').toString(),
        'https://wa.me/919876543210',
      );
      expect(ContactLinks.whatsapp('123'), isNull);
      expect(
        ContactLinks.whatsapp('https://wa.me/123456789').toString(),
        'https://wa.me/123456789',
      );
    });

    test('mailto validates the address', () {
      expect(ContactLinks.mailto('a@b.co').toString(), 'mailto:a@b.co');
      expect(ContactLinks.mailto('not-an-email'), isNull);
    });

    test('web allows http(s) only and upgrades bare hosts', () {
      expect(ContactLinks.web('example.com').toString(), 'https://example.com');
      expect(
        ContactLinks.web('https://x.test/p?q=1').toString(),
        'https://x.test/p?q=1',
      );
      expect(ContactLinks.web('javascript:alert(1)'), isNull);
      expect(ContactLinks.web('data:text/html,hi'), isNull);
      expect(ContactLinks.web('file:///etc/passwd'), isNull);
      expect(ContactLinks.web('intent://scan#Intent;end'), isNull);
    });

    test('map prefers a safe map link, else searches the address', () {
      expect(
        ContactLinks.map(
          mapLink: 'https://maps.app.goo.gl/x',
          address: 'A',
        ).toString(),
        'https://maps.app.goo.gl/x',
      );
      final search = ContactLinks.map(
        mapLink: 'javascript:x',
        address: '1 Main St',
      );
      expect(search?.host, 'www.google.com');
      expect(search?.queryParameters['query'], '1 Main St');
      expect(ContactLinks.map(), isNull);
    });

    test('isAllowed rejects other schemes', () {
      expect(ContactLinks.isAllowed(Uri.parse('tel:123')), isTrue);
      expect(ContactLinks.isAllowed(Uri.parse('sms:123')), isFalse);
      expect(ContactLinks.isAllowed(Uri.parse('javascript:alert(1)')), isFalse);
    });
  });

  test('vcardFileName is filesystem-safe', () {
    expect(vcardFileName('Jane O\'Doe / CEO'), 'Jane_ODoe_CEO.vcf');
    expect(vcardFileName(null), 'contact.vcf');
    expect(vcardFileName('../../..'), 'contact.vcf');
  });
}
