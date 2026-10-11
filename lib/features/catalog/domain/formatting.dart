import 'package:intl/intl.dart';

/// `pending_payment` / `pendingPayment` / `PENDING-PAYMENT` → `Pending payment`.
String humanize(String? raw, {String fallback = 'Unknown'}) {
  if (raw == null || raw.trim().isEmpty) return fallback;
  final spaced = raw
      .trim()
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[_\-.]+'), ' ')
      .toLowerCase();
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// Normalises a wire status (`Pending-Payment` → `pending_payment`).
String wireKey(String? raw) => (raw ?? '')
    .trim()
    .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]}_${m[2]}')
    .replaceAll(RegExp(r'[\s\-.]+'), '_')
    .toLowerCase();

String formatDate(DateTime? d, {String fallback = '—'}) =>
    d == null ? fallback : DateFormat.yMMMd().format(d);

String formatDateTime(DateTime? d, {String fallback = '—'}) =>
    d == null ? fallback : DateFormat.yMMMd().add_jm().format(d);
