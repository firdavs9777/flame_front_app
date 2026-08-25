import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Longest edge, in pixels, a registration photo is reduced to.
const int kMaxPhotoDimension = 800;

/// JPEG quality for the re-encode.
const int kPhotoJpegQuality = 70;

/// Shrinks and re-encodes a photo before upload.
///
/// Lifted out of `RegistrationFlow` and `SocialProfileCompletionFlow`, which
/// each carried a near-identical private copy — the kind of duplication that let
/// their upload paths drift apart in the first place.
///
/// Every failure path returns the ORIGINAL file rather than throwing: a photo
/// that uploads at full size is a slow signup, while a thrown exception is a
/// failed one.
class PhotoCompressor {
  const PhotoCompressor();

  /// Compresses [source] into `<tempDir>/compressed_<index>.jpg`.
  ///
  /// [index] keeps output paths stable and collision-free when several photos
  /// are compressed concurrently.
  Future<File> compress(
    File source, {
    required String tempDir,
    required int index,
  }) async {
    try {
      final bytes = await source.readAsBytes();

      img.Image? image = img.decodeImage(bytes);
      if (image == null) {
        debugPrint('PhotoCompressor: could not decode photo $index, using original');
        return source;
      }

      if (image.width > kMaxPhotoDimension || image.height > kMaxPhotoDimension) {
        image = image.width > image.height
            ? img.copyResize(image, width: kMaxPhotoDimension)
            : img.copyResize(image, height: kMaxPhotoDimension);
      }

      final encoded = img.encodeJpg(image, quality: kPhotoJpegQuality);
      final out = File('$tempDir/compressed_$index.jpg');
      await out.writeAsBytes(encoded);

      debugPrint(
        'PhotoCompressor: photo $index '
        '${(bytes.length / 1024).toStringAsFixed(0)} KB -> '
        '${(encoded.length / 1024).toStringAsFixed(0)} KB',
      );
      return out;
    } catch (e) {
      debugPrint('PhotoCompressor: $e, using original');
      return source;
    }
  }
}
