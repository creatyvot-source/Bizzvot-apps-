import '../../../shared/models/card.dart';
import '../../../shared/models/organization.dart';

/// Recommended precedence (plan §7.2): the organization's private directory
/// wins; a private card is never listed; otherwise the card is listed only
/// while active. The server is authoritative — this drives UI hints only.
bool isListedInDirectory({
  required DirectoryVisibility org,
  required CardVisibility card,
  required bool cardActive,
}) {
  if (org == DirectoryVisibility.private) return false;
  if (card == CardVisibility.private) return false;
  return cardActive;
}

/// Direct link / QR access is independent of directory listing (§7.3).
bool isReachableByLink({required bool cardActive}) => cardActive;

/// Why a card is (not) in the directory, for the owner UI.
String directoryStatusText({
  required DirectoryVisibility org,
  required CardVisibility card,
  required bool cardActive,
}) {
  if (isListedInDirectory(org: org, card: card, cardActive: cardActive)) {
    return 'Listed in the directory';
  }
  if (card == CardVisibility.private) return 'Hidden · card is private';
  if (org == DirectoryVisibility.private) {
    return 'Hidden · directory is private';
  }
  return 'Hidden · card is not active';
}

/// Result of a sequential bulk update.
class BulkResult {
  const BulkResult({required this.succeeded, required this.failed});

  final List<String> succeeded;

  /// Card id → user-safe error message.
  final Map<String, String> failed;

  int get total => succeeded.length + failed.length;
  bool get hasFailures => failed.isNotEmpty;
}
