import 'dart:io';

import 'package:image_picker/image_picker.dart';

import 'package:flame/providers/chat_provider.dart';

/// What a user can attach to a message.
///
/// Deliberately narrower than what the message model can render. The bubble
/// also draws `sticker` and `gif`, but there is no backend for either — all
/// five sticker endpoints 404 by design and no GIF endpoint exists — so
/// offering them would be a dead button. Voice is absent for a different
/// reason: the backend and the player both exist, but there is no recorder UI
/// yet.
enum ChatAttachmentKind {
  gallery,
  camera,
  video;

  /// Whether this kind produces a photo. Gallery and camera differ only in
  /// where the photo comes from.
  bool get isPhoto => this != ChatAttachmentKind.video;
}

/// Picks a file for [kind]. A typedef so a caller can inject a fake and test
/// the send path without a platform picker.
typedef AttachmentPicker = Future<File?> Function(ChatAttachmentKind kind);

/// Opens the platform picker for [kind], or returns null if the user backs out.
///
/// `imageQuality: 85` matches what the rest of the app already uses for photo
/// upload — it also re-encodes HEIC to JPEG, which matters because
/// `ApiClient._mimeTypeForFile` labels an unrecognised extension `image/jpeg`.
Future<File?> pickAttachment(
  ChatAttachmentKind kind, {
  ImagePicker? picker,
}) async {
  final p = picker ?? ImagePicker();

  final picked = switch (kind) {
    ChatAttachmentKind.gallery =>
      await p.pickImage(source: ImageSource.gallery, imageQuality: 85),
    ChatAttachmentKind.camera =>
      await p.pickImage(source: ImageSource.camera, imageQuality: 85),
    ChatAttachmentKind.video =>
      await p.pickVideo(source: ImageSource.gallery),
  };

  return picked == null ? null : File(picked.path);
}

/// Routes a picked file to the sender that matches its kind.
///
/// Returns null on success, or an error message for the caller to surface.
/// Kept separate from the widget so the routing is testable — before this
/// existed, `sendImageMessage` and friends had no callers at all and nothing
/// would have caught wiring a photo to the video endpoint.
Future<String?> sendAttachment({
  required ChatAttachmentKind kind,
  required ConversationsNotifier notifier,
  required String conversationId,
  required File file,
  String? replyToId,
}) {
  return kind.isPhoto
      ? notifier.sendImageMessage(conversationId, file, replyToId: replyToId)
      : notifier.sendVideoMessage(conversationId, file, replyToId: replyToId);
}
