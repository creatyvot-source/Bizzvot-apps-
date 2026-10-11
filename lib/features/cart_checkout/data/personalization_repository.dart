import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utilities/json.dart';
import '../../../shared/models/card.dart';
import '../../../shared/models/paged.dart';

/// A card an NFC product can be linked to. Only public-safe fields.
class LinkableCard {
  const LinkableCard({
    required this.id,
    required this.slug,
    required this.name,
    this.designation,
    this.googleReviewUrl,
  });

  final String id;
  final String slug;
  final String name;
  final String? designation;
  final String? googleReviewUrl;

  factory LinkableCard.fromCard(CardModel c) => LinkableCard(
    id: c.id,
    slug: c.slug,
    name: c.displayTitle,
    designation: c.designation,
    googleReviewUrl: c.googleReviewUrl,
  );
}

/// Uploaded logo reference.
class UploadedLogo {
  const UploadedLogo({required this.url, this.id});
  final String url;
  final String? id;
}

class PickedLogo {
  const PickedLogo({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });
  final String name;
  final Uint8List bytes;
  final String mimeType;
}

/// Picks a logo image. Behind a provider so widget tests can fake it.
abstract class LogoPicker {
  Future<PickedLogo?> pick();
}

class GalleryLogoPicker implements LogoPicker {
  GalleryLogoPicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<PickedLogo?> pick() async {
    final f = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    if (f == null) return null;
    final lower = f.name.toLowerCase();
    final mime = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    return PickedLogo(
      name: f.name,
      bytes: await f.readAsBytes(),
      mimeType: mime,
    );
  }
}

final logoPickerProvider = Provider<LogoPicker>((ref) => GalleryLogoPicker());

/// Data needed to personalise NFC products.
class PersonalizationRepository {
  PersonalizationRepository(this._api);

  final ApiClient _api;

  /// Organization cards (EXISTING `GET /organization/cards`).
  Future<List<LinkableCard>> cards() => _api.get(
    Endpoints.cards,
    query: {'limit': 200},
    parse: (d) =>
        Paged.parse(
              d,
              CardModel.fromJson,
              listKeys: const ['cards', 'items', 'docs', 'data'],
            ).items
            .where((c) => c.id.isNotEmpty)
            .map(LinkableCard.fromCard)
            .toList(growable: false),
  );

  /// EXISTING `POST /media/upload` (multipart `file`).
  Future<UploadedLogo> uploadLogo(PickedLogo logo) => _api.upload(
    Endpoints.mediaUpload,
    form: FormData.fromMap({
      'file': MultipartFile.fromBytes(
        logo.bytes,
        filename: logo.name,
        contentType: DioMediaType.parse(logo.mimeType),
      ),
    }),
    parse: (d) {
      final j = asJson(d);
      final inner = asJson(j['file'] ?? j['media']);
      final url = d is String
          ? d
          : str(j['url'] ?? j['secure_url'] ?? j['location'] ?? inner['url']);
      if (url == null || !url.startsWith('https://')) {
        throw const AppException(
          AppErrorKind.unknown,
          'The logo uploaded but no secure link was returned.',
        );
      }
      return UploadedLogo(
        url: url,
        id: str(j['id'] ?? j['_id'] ?? inner['id']),
      );
    },
  );
}

final personalizationRepositoryProvider = Provider<PersonalizationRepository>(
  (ref) => PersonalizationRepository(ref.watch(apiClientProvider)),
);
