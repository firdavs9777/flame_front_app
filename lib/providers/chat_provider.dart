import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/core/i18n/error_strings_for.dart';

final chatServiceProvider = Provider<ChatService>((ref) => ChatService());

// Conversations provider with async loading from API
final conversationsProvider =
    StateNotifierProvider<
      ConversationsNotifier,
      AsyncValue<List<Conversation>>
    >((ref) {
      final chatService = ref.watch(chatServiceProvider);
      return ConversationsNotifier(chatService);
    });

class ConversationsNotifier
    extends StateNotifier<AsyncValue<List<Conversation>>> {
  final ChatService _chatService;
  bool _hasMore = true;
  int _offset = 0;
  static const int _limit = 20;

  ConversationsNotifier(this._chatService)
      : super(const AsyncValue.loading());

  bool get hasMore => _hasMore;

  Future<void> loadConversations({bool refresh = false}) async {
    if (refresh) {
      _offset = 0;
      _hasMore = true;
      state = const AsyncValue.loading();
    }

    final result = await _chatService.getConversations(
      limit: _limit,
      offset: _offset,
    );

    if (result.success && result.data != null) {
      final conversationsResult = result.data!;
      _hasMore = conversationsResult.hasMore;

      if (refresh || _offset == 0) {
        state = AsyncValue.data(conversationsResult.conversations);
      } else {
        final current = state.valueOrNull ?? [];
        state = AsyncValue.data([
          ...current,
          ...conversationsResult.conversations,
        ]);
      }
      _offset += conversationsResult.conversations.length;
    } else {
      state = AsyncValue.error(
        ErrorStringsFor.fromString(result.error),
        StackTrace.current,
      );
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    await loadConversations();
  }

  // Send methods return null on success and an error message on failure.
  // The error string is what should be shown to the user — for 429 it's the
  // friendly "slow down" message set by ApiClient; for other failures it's
  // the backend's message or a sensible fallback.
  Future<String?> sendMessage(
    String conversationId,
    String content, {
    String? replyToId,
    MessageType type = MessageType.text,
  }) async {
    final result = await _chatService.sendMessage(
      conversationId,
      content,
      type: type,
      replyToId: replyToId,
    );

    if (result.success && result.data != null) {
      final message = result.data!;
      final conversations = state.valueOrNull ?? [];

      state = AsyncValue.data(
        conversations.map((conversation) {
          if (conversation.id == conversationId) {
            return conversation.copyWith(
              messages: [...conversation.messages, message],
              lastMessageAt: DateTime.now(),
            );
          }
          return conversation;
        }).toList(),
      );
      return null;
    }
    return ErrorStringsFor.fromString(result.error);
  }

  Future<String?> sendImageMessage(
    String conversationId,
    File image, {
    String? replyToId,
  }) async {
    final result = await _chatService.sendImageMessage(
      conversationId,
      image,
      replyToId: replyToId,
    );

    if (result.success && result.data != null) {
      final message = result.data!;
      final conversations = state.valueOrNull ?? [];

      state = AsyncValue.data(
        conversations.map((conversation) {
          if (conversation.id == conversationId) {
            return conversation.copyWith(
              messages: [...conversation.messages, message],
              lastMessageAt: DateTime.now(),
            );
          }
          return conversation;
        }).toList(),
      );
      return null;
    }
    return ErrorStringsFor.fromString(result.error);
  }

  Future<String?> sendVideoMessage(
    String conversationId,
    File video, {
    int? duration,
    String? replyToId,
  }) async {
    final result = await _chatService.sendVideoMessage(
      conversationId,
      video,
      duration: duration,
      replyToId: replyToId,
    );

    if (result.success && result.data != null) {
      final message = result.data!;
      final conversations = state.valueOrNull ?? [];

      state = AsyncValue.data(
        conversations.map((conversation) {
          if (conversation.id == conversationId) {
            return conversation.copyWith(
              messages: [...conversation.messages, message],
              lastMessageAt: DateTime.now(),
            );
          }
          return conversation;
        }).toList(),
      );
      return null;
    }
    return ErrorStringsFor.fromString(result.error);
  }

  Future<String?> sendVoiceMessage(
    String conversationId,
    File voice, {
    int? duration,
    String? replyToId,
  }) async {
    final result = await _chatService.sendVoiceMessage(
      conversationId,
      voice,
      duration: duration,
      replyToId: replyToId,
    );

    if (result.success && result.data != null) {
      final message = result.data!;
      final conversations = state.valueOrNull ?? [];

      state = AsyncValue.data(
        conversations.map((conversation) {
          if (conversation.id == conversationId) {
            return conversation.copyWith(
              messages: [...conversation.messages, message],
              lastMessageAt: DateTime.now(),
            );
          }
          return conversation;
        }).toList(),
      );
      return null;
    }
    return ErrorStringsFor.fromString(result.error);
  }

  Future<String?> sendStickerMessage(
    String conversationId,
    String stickerId, {
    String? replyToId,
  }) async {
    final result = await _chatService.sendStickerMessage(
      conversationId,
      stickerId,
      replyToId: replyToId,
    );

    if (result.success && result.data != null) {
      final message = result.data!;
      final conversations = state.valueOrNull ?? [];

      state = AsyncValue.data(
        conversations.map((conversation) {
          if (conversation.id == conversationId) {
            return conversation.copyWith(
              messages: [...conversation.messages, message],
              lastMessageAt: DateTime.now(),
            );
          }
          return conversation;
        }).toList(),
      );
      return null;
    }
    return ErrorStringsFor.fromString(result.error);
  }

  Future<bool> editMessage(
    String conversationId,
    String messageId,
    String newContent,
  ) async {
    final result = await _chatService.editMessage(messageId, newContent);

    if (result.success && result.data != null) {
      _updateMessageInConversation(conversationId, result.data!);
      return true;
    }
    return false;
  }

  Future<bool> deleteMessage(
    String conversationId,
    String messageId, {
    bool forEveryone = false,
  }) async {
    final result = await _chatService.deleteMessage(
      messageId,
      scope: forEveryone ? 'everyone' : 'me',
    );

    if (result.success) {
      if (result.data != null) {
        _updateMessageInConversation(conversationId, result.data!);
      } else {
        _deleteMessageFromConversation(conversationId, messageId);
      }
      return true;
    }
    return false;
  }

  Future<bool> addReaction(
    String conversationId,
    String messageId,
    String emoji,
  ) async {
    final result = await _chatService.addReaction(
      conversationId,
      messageId,
      emoji,
    );
    return result.success;
  }

  Future<bool> removeReaction(String conversationId, String messageId) async {
    final result = await _chatService.removeReaction(conversationId, messageId);
    return result.success;
  }

  Future<bool> markAsRead(String conversationId) async {
    final conversations = state.valueOrNull ?? const <Conversation>[];
    // A stale tap on a conversation that is no longer listed is a no-op, not an
    // exception. This used to be firstWhere(orElse: () => throw), which turned
    // it into an unhandled error.
    if (!conversations.any((c) => c.id == conversationId)) return false;

    // No message ids: the route takes none. Deriving them from local state also
    // gated the call behind an `isEmpty` check, and applyReadReceipt marks local
    // copies read on the OTHER participant's behalf — so their receipt arriving
    // first could suppress ours entirely.
    final result = await _chatService.markMessagesAsRead(conversationId);
    if (!result.success) return false;

    // Re-read rather than reusing the snapshot taken before the PUT. A push
    // landing while it was in flight is applied by addMessageToConversation on
    // this same notifier, and writing the stale list back would drop that
    // message from the preview until the next refetch. That race only became
    // reachable when the socket started calling markAsRead on every push.
    final current = state.valueOrNull ?? const <Conversation>[];
    state = AsyncValue.data(
      current
          .map((c) => c.id == conversationId ? c.copyWith(unreadCount: 0) : c)
          .toList(),
    );
    return true;
  }

  void addMessageToConversation(String conversationId, Message message) {
    final conversations = state.valueOrNull ?? [];
    state = AsyncValue.data(
      conversations.map((conversation) {
        if (conversation.id == conversationId) {
          // Check if message already exists
          if (conversation.messages.any((m) => m.id == message.id)) {
            return conversation;
          }
          return conversation.copyWith(
            messages: [...conversation.messages, message],
            lastMessageAt: message.timestamp,
            unreadCount: conversation.unreadCount + 1,
          );
        }
        return conversation;
      }).toList(),
    );
  }

  /// Archives and drops the conversation from the cached list, so the row
  /// disappears immediately rather than waiting for a refetch.
  ///
  /// Returns null on success, or a message for the caller to show.
  Future<String?> archive(String conversationId) async {
    final result = await _chatService.archiveConversation(conversationId);
    if (!result.success) return ErrorStringsFor.fromString(result.error);

    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.where((c) => c.id != conversationId).toList(),
      );
    }
    return null;
  }

  /// Unarchives.
  ///
  /// The row is not added back to this list: this notifier holds the DEFAULT
  /// list, and whoever calls this is looking at the archived one. They refresh
  /// the default list afterwards.
  Future<String?> unarchive(String conversationId) async {
    final result = await _chatService.unarchiveConversation(conversationId);
    return result.success ? null : ErrorStringsFor.fromString(result.error);
  }

  /// Zeroes the unread badge for one conversation, with no network call.
  ///
  /// Separate from [markAsRead], which also PATCHes the server: when a push
  /// lands for the thread the user already has open, the server has been told
  /// already and only the local badge is stale.
  void clearUnread(String conversationId) {
    final conversations = state.valueOrNull;
    if (conversations == null) return;

    state = AsyncValue.data(
      conversations
          .map((c) => c.id == conversationId ? c.copyWith(unreadCount: 0) : c)
          .toList(),
    );
  }

  /// Applies the other participant's read receipt.
  ///
  /// This marks the messages WE sent as read. It must not touch
  /// [Conversation.unreadCount] — that counts messages waiting for us, and the
  /// other person reading their inbox says nothing about ours. Getting this
  /// backwards would blank the badge every time they opened the thread.
  void applyReadReceipt(String conversationId, String byUserId) {
    final conversations = state.valueOrNull;
    if (conversations == null) return;

    state = AsyncValue.data(
      conversations.map((c) {
        if (c.id != conversationId) return c;
        return c.copyWith(
          messages: c.messages
              .map((m) => m.senderId == byUserId
                  ? m
                  : m.copyWith(status: MessageStatus.read))
              .toList(),
        );
      }).toList(),
    );
  }

  /// Replaces an edited or deleted message in the cached list.
  ///
  /// Without this the Messages preview keeps showing the original text of a
  /// message the sender has since edited or deleted — the list reads
  /// `messages.last`, so a stale entry there is visible on the main screen.
  /// A message we have not cached is ignored: the next fetch brings it in whole.
  void applyMessageUpdate(String conversationId, Message message) {
    final conversations = state.valueOrNull;
    if (conversations == null) return;

    state = AsyncValue.data(
      conversations.map((c) {
        if (c.id != conversationId) return c;
        if (!c.messages.any((m) => m.id == message.id)) return c;
        return c.copyWith(
          messages:
              c.messages.map((m) => m.id == message.id ? message : m).toList(),
        );
      }).toList(),
    );
  }

  /// Flips the online dot in the Messages list.
  ///
  /// Presence used to be whatever the last REST fetch said, so the dots were
  /// only ever correct at load time.
  void applyPresence(String userId, bool online) {
    final conversations = state.valueOrNull;
    if (conversations == null) return;

    state = AsyncValue.data(
      conversations.map((c) {
        if (c.otherUser.id != userId) return c;
        if (c.otherUser.isOnline == online) return c;
        return c.copyWith(otherUser: c.otherUser.copyWith(isOnline: online));
      }).toList(),
    );
  }

  final List<StreamSubscription<void>> _realtimeSubs = [];
  RealtimeConnection? _realtimeConn;

  /// Subscribes the conversation list to the app-level socket.
  ///
  /// Idempotent in two senses. A call with a *different* connection cancels the
  /// first set rather than stacking a duplicate that would count every message
  /// twice. A call with the connection already subscribed does nothing at all —
  /// and that is not just an optimisation. `main_shell` calls this on every
  /// auth-state change; cancelling and re-registering would move these
  /// subscriptions to the END of the broadcast listener order, so an open
  /// ChatScreen's `clearUnread` would then run BEFORE the
  /// `addMessageToConversation` it is meant to cancel out, leaving the badge
  /// showing 1 for the thread the user is looking at.
  void listenToRealtime(RealtimeConnection conn) {
    if (identical(_realtimeConn, conn) && _realtimeSubs.isNotEmpty) return;

    for (final s in _realtimeSubs) {
      s.cancel();
    }
    _realtimeSubs.clear();
    _realtimeConn = conn;

    _realtimeSubs.addAll([
      conn.messageNew.listen((e) {
        final id = e.conversationId;
        if (id != null) addMessageToConversation(id, e.message);
      }),
      conn.messageEdited.listen((e) {
        final id = e.conversationId;
        if (id != null) applyMessageUpdate(id, e.message);
      }),
      conn.messageDeleted.listen((e) {
        final id = e.conversationId;
        if (id != null) applyMessageUpdate(id, e.message);
      }),
      conn.read.listen((e) => applyReadReceipt(e.conversationId, e.byUserId)),
      conn.presence.listen((e) => applyPresence(e.userId, e.online)),
      conn.presenceBulk.listen((ids) {
        final online = ids.toSet();
        for (final c in state.valueOrNull ?? const <Conversation>[]) {
          applyPresence(c.otherUser.id, online.contains(c.otherUser.id));
        }
      }),
    ]);
  }

  @override
  void dispose() {
    for (final s in _realtimeSubs) {
      s.cancel();
    }
    _realtimeSubs.clear();
    _realtimeConn = null;
    super.dispose();
  }

  void _updateMessageInConversation(
    String conversationId,
    Message updatedMessage,
  ) {
    final conversations = state.valueOrNull ?? [];
    state = AsyncValue.data(
      conversations.map((conversation) {
        if (conversation.id == conversationId) {
          return conversation.copyWith(
            messages: conversation.messages.map((m) {
              if (m.id == updatedMessage.id) {
                return updatedMessage;
              }
              return m;
            }).toList(),
          );
        }
        return conversation;
      }).toList(),
    );
  }

  void _deleteMessageFromConversation(String conversationId, String messageId) {
    final conversations = state.valueOrNull ?? [];
    state = AsyncValue.data(
      conversations.map((conversation) {
        if (conversation.id == conversationId) {
          return conversation.copyWith(
            messages: conversation.messages
                .where((m) => m.id != messageId)
                .toList(),
          );
        }
        return conversation;
      }).toList(),
    );
  }
}

final conversationMessagesProvider =
    FutureProvider.family<List<Message>, String>((ref, conversationId) async {
      final chatService = ref.watch(chatServiceProvider);
      final result = await chatService.getMessages(conversationId);

      if (result.success && result.data != null) {
        return result.data!.messages;
      }
      throw Exception(ErrorStringsFor.fromString(result.error));
    });

final selectedConversationProvider = StateProvider<Conversation?>(
  (ref) => null,
);

// Total unread message count across all conversations, driving the Chat
// nav-tab badge and any other unread indicators. Only sums when the
// conversations list has loaded; loading/error states contribute 0.
final chatUnreadCountProvider = Provider<int>((ref) {
  final conversationsState = ref.watch(conversationsProvider);
  return conversationsState.maybeWhen(
    data: (conversations) =>
        conversations.fold(0, (sum, c) => sum + c.unreadCount),
    orElse: () => 0,
  );
});

// Reply to message provider - tracks which message is being replied to
final replyToMessageProvider = StateProvider<Message?>((ref) => null);
