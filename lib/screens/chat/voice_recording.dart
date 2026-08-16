import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Renders a recording length the way a chat does: `0:07`, `1:05`, `12:03`.
///
/// Minutes deliberately keep counting past 60 rather than rolling into an hours
/// field — a voice note that long is a mistake, and `61:00` reads as one where
/// `1:01:00` reads as a feature.
String formatRecordingTime(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// One voice recording, from microphone to a file on disk.
///
/// An interface rather than a bare `AudioRecorder` so the composer can be
/// driven in a test without a microphone, a permission prompt, or a plugin.
abstract class VoiceRecording {
  /// Begins capture. Returns false when permission was refused, which is a
  /// normal answer and not an error.
  Future<bool> start();

  /// Ends capture and returns the recorded file, or null if nothing was
  /// captured.
  Future<File?> stop();

  /// Ends capture and throws the file away.
  Future<void> cancel();

  Future<void> dispose();
}

/// The real thing, over the `record` package.
///
/// Encodes AAC-LC into an `.m4a`, which `ApiClient._mimeTypeForFile` labels
/// `audio/mp4` — one of the types `mediaService.LIMITS.voice` accepts. Change
/// the encoder and that chain has to change with it, or the upload 422s.
class DeviceVoiceRecording implements VoiceRecording {
  DeviceVoiceRecording({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _path;

  @override
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;

    final dir = await getTemporaryDirectory();
    // A stable name per recording; the temp directory is cleared by the OS, and
    // a sent recording is uploaded before anything else needs it.
    _path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: _path!,
    );
    return true;
  }

  @override
  Future<File?> stop() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    final file = File(path);
    return await file.exists() ? file : null;
  }

  @override
  Future<void> cancel() async {
    final path = await _recorder.stop();
    if (path == null) return;
    // Best effort: a leftover temp file is harmless, a crash on discard is not.
    try {
      await File(path).delete();
    } catch (_) {}
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
