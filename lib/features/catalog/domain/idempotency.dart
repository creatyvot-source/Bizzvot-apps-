import 'dart:math';

/// HTTP header carrying the idempotency key on money-moving requests.
const idempotencyHeader = 'Idempotency-Key';

/// RFC 4122 version-4 UUID from a cryptographically secure RNG.
String uuidV4([Random? random]) {
  final rng = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

final _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

bool isUuidV4(String s) => _uuidV4Pattern.hasMatch(s);

/// Generates new idempotency keys. Injectable for tests.
typedef KeyFactory = String Function();

/// Holds the idempotency key of one purchase *attempt*.
///
/// The key is created once when the attempt starts and **reused** for every
/// retry of the same request (network failure, app restart of the screen),
/// so the server can de-duplicate. Changing what is being bought (different
/// plan, quantity or cart) or starting a deliberate new attempt (e.g. retry
/// after a failed payment) must call [reset] / use a new [fingerprint].
class AttemptKey {
  AttemptKey(this._newKey);

  final KeyFactory _newKey;
  String? _key;
  String? _fingerprint;

  /// Key for [fingerprint]; a new key is minted when the fingerprint changes.
  String keyFor(String fingerprint) {
    if (_key == null || _fingerprint != fingerprint) {
      _key = _newKey();
      _fingerprint = fingerprint;
    }
    return _key!;
  }

  String? get current => _key;

  void reset() {
    _key = null;
    _fingerprint = null;
  }
}
