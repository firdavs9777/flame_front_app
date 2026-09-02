import 'package:flutter/material.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/models/models.dart';
import 'package:flame/screens/chat/chat_rows.dart';
import 'package:flame/screens/chat/error/chat_error_widget.dart';
import 'package:flame/screens/chat/message/conversation_empty_state.dart';
import 'package:flame/screens/chat/message/date_separator_chip.dart';
import 'package:flame/screens/chat/state/message_thread_provider.dart';
import 'package:flame/screens/chat/widgets/message_bubble.dart';
import 'package:flame/theme/app_tokens.dart';

/// The thread, rendered.
///
/// Stateless on purpose: it reads a [MessageThreadState] and owns nothing, so the
/// three load states cannot be collapsed by accident and the rows it draws are
/// the memoized ones rather than a fresh `buildChatRows` per rebuild.
class ChatMessagesList extends StatelessWidget {
  const ChatMessagesList({
    super.key,
    required this.state,
    required this.currentUserId,
    required this.otherUserName,
    required this.otherUserPhoto,
    required this.scrollController,
    required this.onRetry,
    required this.onMessageLongPress,
    this.translateDefaultOn = false,
  });

  final MessageThreadState state;
  final String currentUserId;
  final String otherUserName;
  final String otherUserPhoto;
  final ScrollController scrollController;

  /// True when the viewer and the other person have both declared spoken
  /// languages and share none — a known mismatch, computed once by the
  /// screen and applied uniformly to every incoming bubble in the thread.
  /// See `shouldDefaultTranslationOn`.
  final bool translateDefaultOn;

  /// Retries whichever load failed — the initial one, or the older page.
  final VoidCallback onRetry;

  /// One callback for the whole list rather than a closure per bubble: a fresh
  /// closure per build defeats every equality check downstream.
  final void Function(Message) onMessageLongPress;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingInitial) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error before empty. A failure must never render the say-hello prompt.
    final error = state.error;
    if (error != null && state.messages.isEmpty) {
      return ChatErrorWidget(error: error, onRetry: onRetry);
    }

    if (state.isEmpty) {
      return ConversationEmptyState(
        otherUserName: otherUserName,
        otherUserPhoto: otherUserPhoto,
      );
    }

    final rows = state.rows;

    // Older messages load at the top, so whatever reports on that load belongs
    // there too. A failed older page shows a retry rather than a spinner —
    // without it that failure was silent, since the full-surface error only
    // covers an empty thread.
    final hasTopSlot = state.isLoadingMore || error != null;

    return ListView.builder(
      controller: scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(16),
      itemCount: rows.length + (hasTopSlot ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasTopSlot && index == 0) {
          return state.isLoadingMore
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : _OlderPageRetry(onRetry: onRetry);
        }

        final row = rows[hasTopSlot ? index - 1 : index];
        return switch (row) {
          DateSeparatorRow(:final day) => DateSeparatorChip(day: day),
          MessageRow(
            :final message,
            :final isFirstInGroup,
            :final isLastInGroup
          ) =>
            MessageBubble(
              // Without this Flutter reuses element and State across different
              // messages whenever the list shifts — which it does on every
              // prepended page and every push.
              key: ValueKey(message.id),
              message: message,
              isMe: message.isSentBy(currentUserId),
              isFirstInGroup: isFirstInGroup,
              isLastInGroup: isLastInGroup,
              onLongPress: () => onMessageLongPress(message),
              translateDefaultOn: translateDefaultOn,
            ),
        };
      },
    );
  }
}

/// Inline retry for a failed older page, so the failure is visible without
/// wiping the messages already on screen.
class _OlderPageRetry extends StatelessWidget {
  const _OlderPageRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(context.l10n.retry),
          style: TextButton.styleFrom(foregroundColor: context.secondaryText),
        ),
      ),
    );
  }
}
