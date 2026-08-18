import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/chat_provider.dart';
import 'package:flame/screens/chat/state/message_thread_provider.dart';
import 'package:flame/screens/chat/widgets/chat_snackbar.dart';
import 'package:flame/theme/app_theme.dart';

/// Adds an emoji reaction. Fire-and-forget: the provider owns the outcome, and a
/// failed reaction is not worth interrupting the reader for.
Future<void> handleAddReaction({
  required WidgetRef ref,
  required String conversationId,
  required String messageId,
  required String emoji,
}) async {
  await ref
      .read(conversationsProvider.notifier)
      .addReaction(conversationId, messageId, emoji);
}

/// Prompts for new text, then edits via `PATCH /messages/:id` and replaces the
/// message in the open thread on success.
Future<void> handleEditMessage({
  required BuildContext context,
  required WidgetRef ref,
  required String conversationId,
  required Message message,
}) async {
  final controller = TextEditingController(text: message.content);

  final newText = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.chatEditMessage),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(dialogContext.l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: Text(dialogContext.l10n.commonSave),
        ),
      ],
    ),
  );
  controller.dispose();

  if (!context.mounted) return;
  // Unchanged or emptied text is a cancel, not an edit.
  if (newText == null || newText.isEmpty || newText == message.content) return;

  final result =
      await ref.read(chatServiceProvider).editMessage(message.id, newText);
  if (!context.mounted) return;

  if (result.success && result.data != null) {
    ref
        .read(messageThreadProvider(conversationId).notifier)
        .applyUpdate(result.data!);
    return;
  }
  showChatSnackBar(context,
      message: context.l10n.chatEditFailed, type: ChatSnackBarType.error);
}

/// Shows the delete-scope sheet and dispatches the choice.
void handleShowDeleteOptions({
  required BuildContext context,
  required WidgetRef ref,
  required String conversationId,
  required Message message,
}) {
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(sheetContext.l10n.chatDeleteForMe),
            onTap: () {
              Navigator.pop(sheetContext);
              handleDeleteMessage(
                context: context,
                ref: ref,
                conversationId: conversationId,
                message: message,
                scope: 'me',
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: AppTheme.errorColor),
            title: Text(
              sheetContext.l10n.chatDeleteForEveryone,
              style: TextStyle(color: AppTheme.errorColor),
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              handleDeleteMessage(
                context: context,
                ref: ref,
                conversationId: conversationId,
                message: message,
                scope: 'everyone',
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Deletes via `DELETE /messages/:id?scope=` and replaces the message with the
/// returned tombstone.
///
/// The row stays rather than vanishing, so the thread does not reflow under the
/// reader mid-scroll.
Future<void> handleDeleteMessage({
  required BuildContext context,
  required WidgetRef ref,
  required String conversationId,
  required Message message,
  required String scope,
}) async {
  final result = await ref
      .read(chatServiceProvider)
      .deleteMessage(message.id, scope: scope);
  if (!context.mounted) return;

  if (result.success && result.data != null) {
    ref
        .read(messageThreadProvider(conversationId).notifier)
        .applyUpdate(result.data!);
    return;
  }
  showChatSnackBar(context,
      message: context.l10n.chatDeleteFailed, type: ChatSnackBarType.error);
}
