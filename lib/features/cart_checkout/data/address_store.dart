import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/utilities/json.dart';
import '../../catalog/domain/physical_models.dart';

/// Device-local saved delivery addresses, keyed per signed-in user.
///
/// Addresses are personal data, so they live only in Keychain/Keystore
/// backed storage (never SharedPreferences or logs). A server-side address
/// book is preferable and is listed as an API gap.
abstract interface class AddressStore {
  Future<List<ShippingAddress>> load(String userKey);
  Future<void> save(String userKey, List<ShippingAddress> addresses);
}

class SecureAddressStore implements AddressStore {
  SecureAddressStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static String _key(String userKey) =>
      'bv.addresses.${base64Url.encode(utf8.encode(userKey))}';

  @override
  Future<List<ShippingAddress>> load(String userKey) async {
    try {
      final raw = await _storage.read(key: _key(userKey));
      if (raw == null || raw.isEmpty) return const [];
      return asJsonList(jsonDecode(raw))
          .map(ShippingAddress.tryParse)
          .whereType<ShippingAddress>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(String userKey, List<ShippingAddress> addresses) async {
    try {
      await _storage.write(
        key: _key(userKey),
        value: jsonEncode([for (final a in addresses) a.toJson()]),
      );
    } catch (_) {
      // Saving is a convenience; checkout still works without it.
    }
  }
}

class MemoryAddressStore implements AddressStore {
  final Map<String, List<ShippingAddress>> data = {};

  @override
  Future<List<ShippingAddress>> load(String userKey) async =>
      data[userKey] ?? const [];

  @override
  Future<void> save(String userKey, List<ShippingAddress> addresses) async =>
      data[userKey] = List.of(addresses);
}

final addressStoreProvider = Provider<AddressStore>(
  (ref) => SecureAddressStore(),
);
