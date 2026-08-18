import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/chat_provider.dart';
import 'package:flame/screens/chat/chat_attachments.dart';
import 'package:flame/screens/chat/state/message_thread_provider.dart';
import 'package:flame/screens/chat/voice_recording.dart';
import 'package:flame/screens/chat/widgets/attachment_modal.dart';
import 'package:flame/screens/chat/widgets/chat_snackbar.dart';
import 'package:flame/screens/chat/widgets/sticker_panel.dart';

/// What every send path needs from the screen, passed in rather than reached for.
///
/// A record of callbacks instead of a State reference: it is what makes these
/// functions callable from a test without a widget tree, and it names exactly
/// which screen state a send is allowed to touch.
typedef SetSending = void Function(bool);
typedef SetReplyingTo = void Function(Message?);

/// Applies a completed send. Shared by all four paths so the success and failure
/// contracts cannot drift apart between them.
void _applySendResult(
  BuildContext context,
  WidgetRef ref, {
  required String conversationId,
  required SendResult result,
  required Message? sentReplyingTo,
  required SetReplyingTo setReplyingTo,
  required VoidCallback onSent,
}) {
  if (result.ok) {
    // The response already carried the created message, so there is nothing to
    // refetch. Every one of these paths used to await a full newest-page fetch.
    ref
        .read(messageThreadProvider(conversationId).notifier)
        .appendPushed(result.message!);
    onSent();
    return;
  }

  // Put the reply target back: a failed send must not quietly drop what the
  // user was replying to.
  setReplyingTo(sentReplyingTo);
  showChatSnackBar(context,
      message: result.error!, type: ChatSnackBarType.error);
}

/// Sends the composer's text.
Future<void> handleSendText({
  required BuildContext context,
  required WidgetRef ref,
  required String conversationId,
  required TextEditingController controller,
  required Message? replyingTo,
  required SetReplyingTo setReplyingTo,
  required SetSending setSending,
  required VoidCallback onSent,
}) async {
  final content = controller.text.trim();
  if (content.isEmpty) return;

  // Captured before clearing, so a failure can put both back.
  final sentReplyingTo = replyingTo;

  setSending(true);
  setReplyingTo(null);
  controller.clear();

  final result = await ref
      .read(conversationsProvider.notifier)
      .sendMessage(conversationId, content, replyToId: sentReplyingTo?.id);

  if (!context.mounted) return;
  setSending(false);

  if (!result.ok) {
    // Text is restored here rather than in _applySendResult because only this
    // path has a composer to restore.
    controller.text = content;
    controller.selection = TextSelection.collapsed(offset: content.length);
  }

  _applySendResult(context, ref,
      conversationId: conversationId,
      result: result,
      sentReplyingTo: sentReplyingTo,
      setReplyingTo: setReplyingTo,
      onSent: onSent);
}

/// Opens the sticker panel and sends whatever is tapped.
///
/// A sticker is an emoji in the message text, so this is the ordinary send path
/// with a type — no upload, no separate endpoint.
void handleOpenStickerPanel({
  required BuildContext context,
  required WidgetRef ref,
  required String conversationId,
  required Message? replyingTo,
  required SetReplyingTo setReplyingTo,
  required SetSending setSending,
  required VoidCallback onSent,
}) {
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) => StickerPanel(
      onPick: (emoji) {
        Navigator.pop(sheetContext);
        handleSendSticker(
          context: context,
          ref: ref,
          conversationId: conversationId,
          emoji: emoji,
          replyingTo: replyingTo,
          setReplyingTo: setReplyingTo,
          setSending: setSending,
          onSent: onSent,
        );
      },
    ),
  );
}

Future<void> handleSendSticker({
  required BuildContext context,
  required WidgetRef ref,
  required String conversationId,
  required String emoji,
  required Message? replyingTo,
  required SetReplyingTo setReplyingTo,
  required SetSending setSending,
  required VoidCallback onSent,
}) async {
  final sentReplyingTo = replyingTo;

  setSending(true);
  setReplyingTo(null);

  final result = await ref.read(conversationsProvider.notifier).sendMessage(
        conversationId,
        emoji,
        type: MessageType.sticker,
        replyToId: sentReplyingTo?.id,
      );

  if (!context.mounted) return;
  setSending(false);
  _applySendResult(context, ref,
      conversationId: conversationId,
      result: result,
      sentReplyingTo: sentReplyingTo,
      setReplyingTo: setReplyingTo,
      onSent: onSent);
}

/// Opens the share sheet, then picks and sends whatever the user chose.
///
/// Injectable [pick] so the flow can be driven in a test without a platform
/// picker; production passes nothing and gets the real one.
Future<void> handleOpenAttachmentSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String conversationId,
  required Message? replyingTo,
  required SetReplyingTo setReplyingTo,
  required SetSending setSending,
  required VoidCallback onSent,
  AttachmentPicker? pick,
}) async {
  final kind = await showModalBottomSheet<ChatAttachmentKind>(
    context: context,
    builder: (sheetContext) =>
        AttachmentModal(onPick: (k) => Navigator.pop(sheetContext, k)),
  );
  if (kind == null || !context.mounted) return;

  final file = await (pick ?? pickAttachment)(kind);
  // Backing out of the picker is the common case, not an error.
  if (file == null || !context.mounted) return;

  final sentReplyingTo = replyingTo;
  setSending(true);
  setReplyingTo(null);

  final result = await sendAttachment(
    kind: kind,
    notifier: ref.read(conversationsProvider.notifier),
    conversationId: conversationId,
    file: file,
    replyToId: sentReplyingTo?.id,
  );

  if (!context.mounted) return;
  setSending(false);
  _applySendResult(context, ref,
      conversationId: conversationId,
      result: result,
      sentReplyingTo: sentReplyingTo,
      setReplyingTo: setReplyingTo,
      onSent: onSent);
}

/// Starts capture. Returns the live recorder, or null if the mic was refused —
/// the caller holds it, because only the caller can tear it down on dispose.
///
/// Injectable [make] so the flow is drivable in a test without a microphone or a
/// permission prompt.
Future<VoiceRecording?> handleStartRecording({
  required BuildContext context,
  VoiceRecording Function()? make,
}) async {
  final rec = (make ?? DeviceVoiceRecording.new)();
  if (!await rec.start()) {
    await rec.dispose();
    if (context.mounted) {
      showChatSnackBar(context,
          message: context.l10n.chatMicPermission,
          type: ChatSnackBarType.error);
    }
    return null;
  }
  if (!context.mounted) {
    // The screen went away mid-permission-prompt; do not leave the mic open.
    await rec.cancel();
    await rec.dispose();
    return null;
  }
  return rec;
}

/// Stops [rec] and sends what it captured.
///
/// A recording that captured nothing is a mis-tap, not a message — a tap that
/// started and stopped inside the same second — so it sends nothing.
Future<void> handleSendRecording({
  required BuildContext context,
  required WidgetRef ref,
  required String conversationId,
  required VoiceRecording rec,
  required int seconds,
  required Message? replyingTo,
  required SetReplyingTo setReplyingTo,
  required SetSending setSending,
  required VoidCallback onSent,
}) async {
  final sentReplyingTo = replyingTo;

  final file = await rec.stop();
  await rec.dispose();
  if (!context.mounted || file == null) return;

  setSending(true);
  setReplyingTo(null);

  final result = await ref.read(conversationsProvider.notifier).sendVoiceMessage(
        conversationId,
        file,
        duration: seconds,
        replyToId: sentReplyingTo?.id,
      );

  if (!context.mounted) return;
  setSending(false);
  _applySendResult(context, ref,
      conversationId: conversationId,
      result: result,
      sentReplyingTo: sentReplyingTo,
      setReplyingTo: setReplyingTo,
      onSent: onSent);
}
