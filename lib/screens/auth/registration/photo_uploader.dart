import 'dart:io';

/// Result of uploading a single photo.
class UploadOutcome {
  final bool success;
  final String? url;

  const UploadOutcome({required this.success, this.url});
}

/// Uploads registration photos in parallel with per-photo retry, preserving
/// the original order of successful uploads.
///
/// The network work is injected via [uploadOne] so this is fully unit-testable
/// without hitting the network or a device. Registration photo count is small
/// (<=6), so unbounded `Future.wait` fan-out is fine.
class PhotoUploader {
  const PhotoUploader();

  /// Uploads [files] concurrently. Each file is retried ONCE on failure. The
  /// first file (index 0) is flagged as primary. Returns the successfully
  /// uploaded URLs in the same order as [files]; files that fail even after
  /// the retry are dropped (their slot is omitted, order otherwise preserved).
  Future<List<String>> upload(
    List<File> files, {
    required Future<UploadOutcome> Function(File file, {required bool isPrimary})
        uploadOne,
  }) async {
    if (files.isEmpty) return [];

    Future<UploadOutcome> attempt(File file, bool isPrimary) async {
      final first = await uploadOne(file, isPrimary: isPrimary);
      if (first.success && first.url != null) return first;
      // Retry once on failure.
      return uploadOne(file, isPrimary: isPrimary);
    }

    final futures = <Future<UploadOutcome>>[];
    for (var i = 0; i < files.length; i++) {
      futures.add(attempt(files[i], i == 0));
    }

    final outcomes = await Future.wait(futures);

    final urls = <String>[];
    for (final outcome in outcomes) {
      if (outcome.success && outcome.url != null) {
        urls.add(outcome.url!);
      }
    }
    return urls;
  }
}
