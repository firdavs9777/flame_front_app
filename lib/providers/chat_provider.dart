import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
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

  ConversationsNotifier(this._chatService) : super(const AsyncValue.loading()) {
    _initWebSocket();
  }

  bool get hasMore => _hasMore;

  /// Realtime is owned by the screen that displays a conversation, not by this
  /// provider. [ChatScreen] constructs a [FlameSocketService] against the
  /// backend's `/flame` Socket.IO namespace and wires its own callbacks.
  ///
  /// This used to connect `WebSocketService` to `wss://<host>/ws`, an endpoint
  /// that does not exist on the server — it only ever produced an endless
  /// reconnect loop, and its event names (`new_message`, `user_online`, …) did
  /// not match anything `flameSocket.js` emits.
  void _initWebSocket() {}

  void _onNewMessage(Map<String, dynamic> data) {
    debugPrint('📨 _onNewMessage called with data: $data');

    final conversationId = data['conversation_id'] as String?;
    final messageData = data['message'] as Map<String, dynamic>?;

    debugPrint('📨 conversationId: $conversationId, messageData: $messageData');

    if (conversationId == null || messageData == null) {
      debugPrint('📨 Missing conversationId or messageData, returning early');
      return;
    }

    try {
      final message = Message.fromJson(messageData);
      debugPrint('📨 Parsed message: ${message.id} - ${message.content}');
      addMessageToConversation(conversationId, message);
      debugPrint('📨 Message added to conversation successfully');
    } catch (e, stack) {
      debugPrint('📨 Error parsing message: $e');
      debugPrint('📨 Stack: $stack');
    }
  }

  void _onMessageStatus(Map<String, dynamic> data) {
    final conversationId = data['conversation_id'] as String?;
    final messageIds = (data['message_ids'] as List?)?.cast<String>() ?? [];
    final status = data['status'] as String?;

    if (conversationId == null || status == null) return;

    updateMessageStatus(
      conversationId,
      messageIds,
      MessageStatus.fromString(status),
    );
  }

  void _onUserOnline(Map<String, dynamic> data) {
    final userId = data['user_id'] as String?;
    if (userId == null) return;
    updateUserOnlineStatus(userId, true);
  }

  void _onUserOffline(Map<String, dynamic> data) {
    final userId = data['user_id'] as String?;
    if (userId == null) return;
    updateUserOnlineStatus(userId, false);
  }

  void _onMessageEdited(Map<String, dynamic> data) {
    final conversationId = data['conversation_id'] as String?;
    final messageData = data['message'] as Map<String, dynamic>?;

    if (conversationId == null || messageData == null) return;

    final updatedMessage = Message.fromJson(messageData);
    _updateMessageInConversation(conversationId, updatedMessage);
  }

  void _onMessageDeleted(Map<String, dynamic> data) {
    final conversationId = data['conversation_id'] as String?;
    final messageId = data['message_id'] as String?;

    if (conversationId == null || messageId == null) return;

    _deleteMessageFromConversation(conversationId, messageId);
  }

  void _onReactionAdded(Map<String, dynamic> data) {
    final conversationId = data['conversation_id'] as String?;
    final messageId = data['message_id'] as String?;
    final emoji = data['emoji'] as String?;
    final userId = data['user_id'] as String?;

    if (conversationId == null ||
        messageId == null ||
        emoji == null ||
        userId == null)
      return;

    _addReactionToMessage(conversationId, messageId, emoji, userId);
  }

  void _onReactionRemoved(Map<String, dynamic> data) {
    final conversationId = data['conversation_id'] as String?;
    final messageId = data['message_id'] as String?;
    final userId = data['user_id'] as String?;

    if (conversationId == null || messageId == null || userId == null) return;

    _removeReactionFromMessage(conversationId, messageId, userId);
  }

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

  void _addReactionToMessage(
    String conversationId,
    String messageId,
    String emoji,
    String userId,
  ) {
    final conversations = state.valueOrNull ?? [];
    state = AsyncValue.data(
      conversations.map((conversation) {
        if (conversation.id == conversationId) {
          return conversation.copyWith(
            messages: conversation.messages.map((m) {
              if (m.id == messageId) {
                // Remove any existing reaction from this user
                final filteredReactions = m.reactions
                    .where((r) => r.userId != userId)
                    .toList();
                return m.copyWith(
                  reactions: [
                    ...filteredReactions,
                    MessageReaction(
                      emoji: emoji,
                      userId: userId,
                      createdAt: DateTime.now(),
                    ),
                  ],
                );
              }
              return m;
            }).toList(),
          );
        }
        return conversation;
      }).toList(),
    );
  }

  void _removeReactionFromMessage(
    String conversationId,
    String messageId,
    String userId,
  ) {
    final conversations = state.valueOrNull ?? [];
    state = AsyncValue.data(
      conversations.map((conversation) {
        if (conversation.id == conversationId) {
          return conversation.copyWith(
            messages: conversation.messages.map((m) {
              if (m.id == messageId) {
                return m.copyWith(
                  reactions: m.reactions
                      .where((r) => r.userId != userId)
                      .toList(),
                );
              }
              return m;
            }).toList(),
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
