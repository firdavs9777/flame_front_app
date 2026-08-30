import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/models/models.dart';
import 'package:flame/screens/chat/conversation/handlers/message_actions.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/theme/app_tokens.dart';

/// Opens the long-press sheet for [message] and routes each choice to its
/// handler.
///
/// Lives here rather than on the screen: deciding which rows a message may show,
/// and popping the sheet before acting, is sheet wiring — the screen only needs
/// to supply the two things it owns (its pin list and its reply target).
void showMessageActions({
  required BuildContext context,
  required WidgetRef ref,
  required String conversationId,
  required Message message,
  required String currentUserId,
  required bool isPinned,
  required VoidCallback onTogglePin,
  required VoidCallback onReply,
  required VoidCallback onReport,
}) {
  // Edit and delete are offered only on the current user's own, not-yet-deleted
  // messages.
  final isOwn = message.isSentBy(currentUserId) && !message.isDeleted;

  showModalBottomSheet(
    context: context,
    builder: (sheetContext) => MessageActionsSheet(
      isPinned: isPinned,
      onTogglePin: () {
        Navigator.pop(sheetContext);
        onTogglePin();
      },
      onReply: () {
        Navigator.pop(sheetContext);
        onReply();
      },
      onReact: (emoji) {
        Navigator.pop(sheetContext);
        handleAddReaction(
          ref: ref,
          conversationId: conversationId,
          messageId: message.id,
          emoji: emoji,
        );
      },
      onEdit: isOwn
          ? () {
              Navigator.pop(sheetContext);
              handleEditMessage(
                context: context,
                ref: ref,
                conversationId: conversationId,
                message: message,
              );
            }
          : null,
      onDelete: isOwn
          ? () {
              Navigator.pop(sheetContext);
              handleShowDeleteOptions(
                context: context,
                ref: ref,
                conversationId: conversationId,
                message: message,
              );
            }
          : null,
      // You cannot report yourself, and a deleted message has no content left
      // to moderate.
      onReport: isOwn || message.isDeleted
          ? null
          : () {
              Navigator.pop(sheetContext);
              onReport();
            },
    ),
  );
}

class MessageActionsSheet extends StatelessWidget {
  final VoidCallback onReply;
  final void Function(String emoji) onReact;
  // Non-null only for the current user's own, not-yet-deleted messages —
  // their presence gates whether the Edit/Delete rows are shown at all.
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Non-null only for someone else's live message. Apple's UGC rules expect
  /// the offending content to be reportable, not just its author.
  final VoidCallback? onReport;

  /// Pin state and toggle. Pinning is per-user, so this reflects whether the
  /// CALLER has pinned it, not whether anyone has.
  final bool isPinned;
  final VoidCallback onTogglePin;

  const MessageActionsSheet({
    super.key,
    required this.onReply,
    required this.onReact,
    required this.isPinned,
    required this.onTogglePin,
    this.onEdit,
    this.onDelete,
    this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick reactions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['❤️', '😂', '😮', '😢', '😡', '👍'].map((emoji) {
                return GestureDetector(
                  onTap: () => onReact(emoji),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.fill,
                      shape: BoxShape.circle,
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
            title: Text(isPinned ? context.l10n.chatUnpin : context.l10n.chatPin),
            onTap: onTogglePin,
          ),
          ListTile(
            leading: const Icon(Icons.reply),
            title: Text(context.l10n.chatReply),
            onTap: onReply,
          ),
          if (onEdit != null)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(context.l10n.chatEdit),
              onTap: onEdit,
            ),
          if (onDelete != null)
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppTheme.errorColor),
              title: Text(context.l10n.chatDelete,
                  style: TextStyle(color: AppTheme.errorColor)),
              onTap: onDelete,
            ),
          if (onReport != null)
            ListTile(
              leading: Icon(Icons.flag_outlined, color: AppTheme.errorColor),
              title: Text(context.l10n.safetyReportMessage,
                  style: TextStyle(color: AppTheme.errorColor)),
              onTap: onReport,
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// A day boundary in the conversation.