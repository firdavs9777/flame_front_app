import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/providers/chat_provider.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/screens/chat/widgets/chat_snackbar.dart';
import 'package:flame/services/chat_service.dart' show PinnedMessage;

/// Free functions rather than methods on the screen's State.
///
/// Each takes everything it needs by named parameter, so the orchestrator calls
/// it in one line and a test calls it directly without pumping the whole chat.
/// Following `bananatalk_app/lib/pages/chat/conversation/handlers/`.

/// Tells the server we read the thread, and the partner over the socket.
///
/// Unconditional: it used to be gated behind "are any loaded messages unread",
/// which meant a receipt from the partner arriving first could suppress ours.
Future<void> handleMarkRead({
  required WidgetRef ref,
  required String conversationId,
  required String otherUserId,
  required RealtimeConnection connection,
}) async {
  ref.read(conversationsProvider.notifier).clearUnread(conversationId);
  await ref.read(conversationsProvider.notifier).markAsRead(conversationId);
  connection.socket?.emitMarkRead(otherUserId, conversationId);
}

/// The caller's pinned messages for this conversation, or an empty list.
Future<List<PinnedMessage>> handleLoadPinned({
  required WidgetRef ref,
  required String conversationId,
}) async {
  final result =
      await ref.read(chatServiceProvider).getPinnedMessages(conversationId);
  return result.success ? (result.data ?? const []) : const [];
}

/// Pins [messageId] and returns the caller's full pin list.
///
/// The endpoint answers with the whole list, so callers replace rather than
/// append — merging would drift from the server's view. Returns [current]
/// unchanged on failure.
Future<List<PinnedMessage>> handlePin({
  required BuildContext context,
  required WidgetRef ref,
  required String conversationId,
  required String messageId,
  required List<PinnedMessage> current,
}) async {
  final result =
      await ref.read(chatServiceProvider).pinMessage(conversationId, messageId);
  if (result.success) return result.data ?? const [];

  showChatSnackBar(context,
      message: context.l10n.chatPinFailed, type: ChatSnackBarType.error);
  return current;
}

/// Unpins [messageId], returning the list without it. [current] unchanged on
/// failure.
Future<List<PinnedMessage>> handleUnpin({
  required BuildContext context,
  required WidgetRef ref,
  required String conversationId,
  required String messageId,
  required List<PinnedMessage> current,
}) async {
  final result = await ref
      .read(chatServiceProvider)
      .unpinMessage(conversationId, messageId);
  if (result.success) {
    return current.where((p) => p.messageId != messageId).toList();
  }

  showChatSnackBar(context,
      message: context.l10n.chatUnpinFailed, type: ChatSnackBarType.error);
  return current;
}

/// Flips mute. Returns the state the caller should hold — the requested one on
/// success, the previous one on failure.
Future<bool> handleToggleMute({
  required BuildContext context,
  required WidgetRef ref,
  required String conversationId,
  required bool wasMuted,
}) async {
  final service = ref.read(chatServiceProvider);
  final result = wasMuted
      ? await service.unmuteConversation(conversationId)
      : await service.muteConversation(conversationId);

  if (result.success) return !wasMuted;

  showChatSnackBar(context,
      message: context.l10n.chatMuteFailed, type: ChatSnackBarType.error);
  return wasMuted;
}
