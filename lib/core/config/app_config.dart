import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/endpoints.dart';
import '../providers.dart';
import '../utilities/json.dart';

/// Server-driven app configuration (PROPOSED `GET /app/config`, gap CFG-1).
///
/// Everything that may change without an app release lives here: minimum
/// supported version, maintenance mode, legal/support links and feature
/// flags. When the endpoint is unreachable the app falls back to
/// [AppConfig.defaults] (fail-open) so a config outage never locks users out.
class AppConfig {
  const AppConfig({
    this.minSupportedVersion,
    this.latestVersion,
    this.maintenance = false,
    this.maintenanceMessage,
    this.privacyPolicyUrl,
    this.termsUrl,
    this.analyticsDisclosureUrl,
    this.supportEmail,
    this.supportPhone,
    this.androidStoreUrl,
    this.iosStoreUrl,
    this.refundPolicyUrl,
    this.shippingPolicyUrl,
    this.cancellationPolicyUrl,
    this.termsVersion,
    this.seller,
    this.grievanceOfficer,
    this.features = const {},
  });

  final String? minSupportedVersion;
  final String? latestVersion;
  final bool maintenance;
  final String? maintenanceMessage;
  final String? privacyPolicyUrl;
  final String? termsUrl;
  final String? analyticsDisclosureUrl;
  final String? supportEmail;
  final String? supportPhone;
  final String? androidStoreUrl;
  final String? iosStoreUrl;

  /// Consumer Protection (E-Commerce) Rules 2020 disclosures.
  final String? refundPolicyUrl;
  final String? shippingPolicyUrl;
  final String? cancellationPolicyUrl;

  /// Version of the terms the user accepts at registration (sent to the
  /// server so consent can be proven — DPDP Act 2023).
  final String? termsVersion;
  final SellerInfo? seller;
  final GrievanceOfficer? grievanceOfficer;

  /// Remote feature flags. Unknown flags default to enabled so a missing
  /// key never hides a shipped feature.
  final Map<String, bool> features;

  static const defaults = AppConfig();

  bool isEnabled(String flag) => features[flag] ?? true;

  factory AppConfig.fromJson(Object? raw) {
    final j = asJson(raw);
    final maintenance = j['maintenance'];
    final links = asJson(j['links']);
    final support = asJson(j['support']);
    final store = asJson(j['store'] ?? j['storeUrls']);
    final version = asJson(j['version']);
    return AppConfig(
      minSupportedVersion: str(j['minSupportedVersion']) ?? str(version['min']),
      latestVersion: str(j['latestVersion']) ?? str(version['latest']),
      maintenance: maintenance is Map
          ? boolOr(maintenance['active'])
          : boolOr(maintenance),
      maintenanceMessage: maintenance is Map
          ? str(maintenance['message'])
          : str(j['maintenanceMessage']),
      privacyPolicyUrl: str(links['privacyPolicy']) ?? str(j['privacyPolicyUrl']),
      termsUrl: str(links['terms']) ?? str(j['termsUrl']),
      analyticsDisclosureUrl:
          str(links['analyticsDisclosure']) ?? str(j['analyticsDisclosureUrl']),
      supportEmail: str(support['email']) ?? str(j['supportEmail']),
      supportPhone: str(support['phone']) ?? str(j['supportPhone']),
      androidStoreUrl: str(store['android']),
      iosStoreUrl: str(store['ios']),
      refundPolicyUrl: str(links['refundPolicy']),
      shippingPolicyUrl: str(links['shippingPolicy']),
      cancellationPolicyUrl: str(links['cancellationPolicy']),
      termsVersion: str(j['termsVersion']) ?? str(links['termsVersion']),
      seller: j['seller'] is Map ? SellerInfo.fromJson(j['seller']) : null,
      grievanceOfficer: j['grievanceOfficer'] is Map
          ? GrievanceOfficer.fromJson(j['grievanceOfficer'])
          : null,
      features: asJson(j['features']).map((k, v) => MapEntry(k, boolOr(v, true))),
    );
  }
}

/// Legal seller identity shown on legal screens and invoices.
class SellerInfo {
  const SellerInfo({required this.legalName, this.address, this.gstin, this.email, this.phone});

  final String legalName;
  final String? address;
  final String? gstin;
  final String? email;
  final String? phone;

  factory SellerInfo.fromJson(Object? raw) {
    final j = asJson(raw);
    return SellerInfo(
      legalName: strOr(j['legalName'] ?? j['name']),
      address: str(j['address']),
      gstin: str(j['gstin']),
      email: str(j['email']),
      phone: str(j['phone']),
    );
  }
}

/// Grievance officer (IT Rules 2011/2021, E-Commerce Rules 2020, DPDP Act).
class GrievanceOfficer {
  const GrievanceOfficer({required this.name, this.email, this.phone, this.address});

  final String name;
  final String? email;
  final String? phone;
  final String? address;

  factory GrievanceOfficer.fromJson(Object? raw) {
    final j = asJson(raw);
    return GrievanceOfficer(
      name: strOr(j['name']),
      email: str(j['email']),
      phone: str(j['phone']),
      address: str(j['address']),
    );
  }
}

/// Known feature-flag keys.
abstract final class Flags {
  static const shop = 'shop';
  static const directory = 'directory';
  static const notifications = 'notifications';
  static const accountDeletion = 'accountDeletion';
}

/// Compares dotted versions (`1.10.2` > `1.9`). Non-numeric parts count as 0.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split('+')
      .first
      .split('.')
      .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

enum UpdateRequirement { none, optional, required }

UpdateRequirement updateRequirement(AppConfig config, String current) {
  final min = config.minSupportedVersion;
  if (min != null && compareVersions(current, min) < 0) {
    return UpdateRequirement.required;
  }
  final latest = config.latestVersion;
  if (latest != null && compareVersions(current, latest) < 0) {
    return UpdateRequirement.optional;
  }
  return UpdateRequirement.none;
}

/// Installed app version, e.g. `0.1.0`.
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    return (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    return '0.0.0';
  }
});

/// Remote config; falls back to defaults on any failure.
final appConfigProvider = FutureProvider<AppConfig>((ref) async {
  try {
    return await ref.watch(apiClientProvider).get(
          Endpoints.appConfig,
          parse: AppConfig.fromJson,
          anonymous: true,
        );
  } catch (_) {
    return AppConfig.defaults;
  }
});

/// Synchronous accessor for widgets: defaults until loaded.
final currentConfigProvider = Provider<AppConfig>(
  (ref) => ref.watch(appConfigProvider).value ?? AppConfig.defaults,
);
