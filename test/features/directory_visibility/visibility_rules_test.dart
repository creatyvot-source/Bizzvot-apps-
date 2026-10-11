import 'package:bizzvot/features/directory_visibility/domain/visibility_rules.dart';
import 'package:bizzvot/shared/models/card.dart';
import 'package:bizzvot/shared/models/organization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isListedInDirectory (plan §7.2 recommended precedence)', () {
    // (org, card, active) → listed
    final matrix = <(DirectoryVisibility, CardVisibility, bool, bool)>[
      (DirectoryVisibility.public, CardVisibility.inherit, true, true),
      (DirectoryVisibility.public, CardVisibility.public, true, true),
      (DirectoryVisibility.public, CardVisibility.private, true, false),
      (DirectoryVisibility.private, CardVisibility.inherit, true, false),
      // Org-level private wins over a card-level public override.
      (DirectoryVisibility.private, CardVisibility.public, true, false),
      (DirectoryVisibility.private, CardVisibility.private, true, false),
      // Inactive cards are never listed.
      (DirectoryVisibility.public, CardVisibility.inherit, false, false),
      (DirectoryVisibility.public, CardVisibility.public, false, false),
    ];
    for (final (org, card, active, listed) in matrix) {
      test('org=${org.wire} card=${card.wire} active=$active → $listed', () {
        expect(
          isListedInDirectory(org: org, card: card, cardActive: active),
          listed,
        );
      });
    }
  });

  test('direct link access ignores directory privacy', () {
    expect(isReachableByLink(cardActive: true), isTrue);
    expect(isReachableByLink(cardActive: false), isFalse);
  });

  test('status text explains the deciding rule', () {
    expect(
      directoryStatusText(
        org: DirectoryVisibility.public,
        card: CardVisibility.inherit,
        cardActive: true,
      ),
      'Listed in the directory',
    );
    expect(
      directoryStatusText(
        org: DirectoryVisibility.private,
        card: CardVisibility.public,
        cardActive: true,
      ),
      contains('directory is private'),
    );
    expect(
      directoryStatusText(
        org: DirectoryVisibility.private,
        card: CardVisibility.private,
        cardActive: true,
      ),
      contains('card is private'),
    );
    expect(
      directoryStatusText(
        org: DirectoryVisibility.public,
        card: CardVisibility.public,
        cardActive: false,
      ),
      contains('not active'),
    );
  });
}
