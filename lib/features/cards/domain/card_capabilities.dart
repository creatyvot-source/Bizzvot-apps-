import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';

/// Card features whose backend support is not live yet (see
/// `docs/audit/01-api-contract.md` and `CardWire.unsupportedFields`).
///
/// Each defaults to OFF. The UI keeps these sections visible but read-only
/// with a "Coming soon" note, and nothing is sent for them. A server
/// feature flag set **explicitly** to `true` in `GET /app/config` turns one
/// on without an app release (unknown flags must not enable half-built
/// features, so `AppConfig.isEnabled`'s default-on is not used here).
class CardCapabilities {
  const CardCapabilities({
    this.privateDetails = false,
    this.companyPhone = false,
    this.media = false,
    this.documents = false,
    this.visibility = false,
    this.googleReview = false,
    this.extendedTemplates = false,
  });

  /// Blood group, father's/mother's name.
  final bool privateDetails;
  final bool companyPhone;

  /// Gallery images and YouTube videos.
  final bool media;

  /// PDF upload (`POST /cards/:id/media`) and library removal.
  final bool documents;

  /// Per-card `visibility` and the organization `directoryVisibility`.
  final bool visibility;
  final bool googleReview;

  /// `profile_hub`, `cover_card`, `review_card` templates.
  final bool extendedTemplates;

  static const backend = CardCapabilities();

  static const all = CardCapabilities(
    privateDetails: true,
    companyPhone: true,
    media: true,
    documents: true,
    visibility: true,
    googleReview: true,
    extendedTemplates: true,
  );

  factory CardCapabilities.fromFlags(Map<String, bool> f) => CardCapabilities(
        privateDetails: f['cardPrivateDetails'] == true,
        companyPhone: f['cardCompanyPhone'] == true,
        media: f['cardMedia'] == true,
        documents: f['cardDocuments'] == true,
        visibility: f['cardVisibility'] == true,
        googleReview: f['cardGoogleReview'] == true,
        extendedTemplates: f['cardExtendedTemplates'] == true,
      );
}

final cardCapabilitiesProvider = Provider<CardCapabilities>(
  (ref) => CardCapabilities.fromFlags(ref.watch(currentConfigProvider).features),
);
