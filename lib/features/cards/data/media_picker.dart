import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// A file chosen on the device, already read into memory (≤ 10 MB by the
/// media rules, so this is safe).
class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Platform pickers behind an interface so widget tests can inject fakes
/// (image_picker / file_picker channels do not exist in tests).
abstract class MediaPicker {
  /// One image from the photo library, or `null` when cancelled.
  Future<PickedFile?> pickImage();

  /// Up to [limit] images from the photo library.
  Future<List<PickedFile>> pickImages({required int limit});

  /// Up to [limit] PDF documents.
  Future<List<PickedFile>> pickPdfs({required int limit});
}

final mediaPickerProvider = Provider<MediaPicker>((ref) => PlatformMediaPicker());

class PlatformMediaPicker implements MediaPicker {
  PlatformMediaPicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  // Re-encode large photos on device; the server still enforces 5 MB.
  static const _maxDimension = 2048.0;
  static const _quality = 85;

  @override
  Future<PickedFile?> pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: _maxDimension,
      maxHeight: _maxDimension,
      imageQuality: _quality,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    return PickedFile(name: file.name, bytes: await file.readAsBytes());
  }

  @override
  Future<List<PickedFile>> pickImages({required int limit}) async {
    if (limit <= 0) return const [];
    final files = limit == 1
        ? [?await _picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: _maxDimension,
            maxHeight: _maxDimension,
            imageQuality: _quality,
            requestFullMetadata: false,
          )]
        : await _picker.pickMultiImage(
            maxWidth: _maxDimension,
            maxHeight: _maxDimension,
            imageQuality: _quality,
            limit: limit,
            requestFullMetadata: false,
          );
    return [
      for (final f in files.take(limit))
        PickedFile(name: f.name, bytes: await f.readAsBytes()),
    ];
  }

  @override
  Future<List<PickedFile>> pickPdfs({required int limit}) async {
    if (limit <= 0) return const [];
    final files = await fp.FilePicker.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    return [
      for (final f in files.take(limit))
        PickedFile(name: f.name, bytes: await f.readAsBytes()),
    ];
  }
}
