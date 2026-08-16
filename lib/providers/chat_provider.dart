import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/core/i18n/error_strings_for.dart';
import 'package:flame/config/env.dart';

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
  }) async {
    final result = await _chatService.sendMessage(
      conversationId,
      content,
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
    final conversations = state.valueOrNull ?? [];
    final conversation = conversations.firstWhere(
      (c) => c.id == conversationId,
      orElse: () => throw Exception('Conversation not found'),
    );

    // Get unread message IDs
    final unreadMessageIds = conversation.messages
        .where((m) => m.status != MessageStatus.read)
        .map((m) => m.id)
        .toList();

    if (unreadMessageIds.isEmpty) return true;

    final result = await _chatService.markMessagesAsRead(
      conversationId,
      unreadMessageIds,
    );

    if (result.success) {
      state = AsyncValue.data(
        conversations.map((c) {
          if (c.id == conversationId) {
            return c.copyWith(
              unreadCount: 0,
              messages: c.messages
                  .map((m) => m.copyWith(status: MessageStatus.read))
                  .toList(),
            );
          }
          return c;
        }).toList(),
      );
      return true;
    }
    return false;
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

  /// Subscribes the conversation list to the app-level socket.
  ///
  /// Idempotent: a second call cancels the first set rather than stacking a
  /// duplicate that would count every message twice.
  void listenToRealtime(RealtimeConnection conn) {
    for (final s in _realtimeSubs) {
      s.cancel();
    }
    _realtimeSubs.clear();

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

  void updateMessageStatus(
    String conversationId,
    List<String> messageIds,
    MessageStatus status,
  ) {
    final conversations = state.valueOrNull ?? [];
    state = AsyncValue.data(
      conversations.map((conversation) {
        if (conversation.id == conversationId) {
          return conversation.copyWith(
            messages: conversation.messages.map((m) {
              if (messageIds.contains(m.id)) {
                return m.copyWith(status: status);
              }
              return m;
            }).toList(),
          );
        }
        return conversation;
      }).toList(),
    );
  }

  void updateUserOnlineStatus(String userId, bool isOnline) {
    final conversations = state.valueOrNull ?? [];
    state = AsyncValue.data(
      conversations.map((conversation) {
        if (conversation.otherUser.id == userId) {
          return conversation.copyWith(
            otherUser: conversation.otherUser.copyWith(isOnline: isOnline),
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
