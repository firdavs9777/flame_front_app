import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/services/websocket_service.dart';

final chatServiceProvider = Provider<ChatService>((ref) => ChatService());
final webSocketServiceProvider = Provider<WebSocketService>((ref) => WebSocketService());

// Conversations provider with async loading from API
final conversationsProvider = StateNotifierProvider<ConversationsNotifier, AsyncValue<List<Conversation>>>((ref) {
  final chatService = ref.watch(chatServiceProvider);
  final wsService = ref.watch(webSocketServiceProvider);
  return ConversationsNotifier(chatService, wsService);
});

class ConversationsNotifier extends StateNotifier<AsyncValue<List<Conversation>>> {
  final ChatService _chatService;
  final WebSocketService _wsService;
  bool _hasMore = true;
  int _offset = 0;
  static const int _limit = 20;

  ConversationsNotifier(this._chatService, this._wsService) : super(const AsyncValue.loading()) {
    _initWebSocket();
  }

  bool get hasMore => _hasMore;

  void _initWebSocket() {
    debugPrint('🔌 _initWebSocket: Setting up WebSocket listeners');

    // Connect to WebSocket
    _wsService.connect();

    // Listen for new messages
    debugPrint('🔌 Registering listener for: ${WebSocketServerEvent.newMessage}');
    _wsService.on(WebSocketServerEvent.newMessage, _onNewMessage);

    // Listen for message status updates
    _wsService.on(WebSocketServerEvent.messageStatus, _onMessageStatus);

    // Listen for user online/offline
    _wsService.on(WebSocketServerEvent.userOnline, _onUserOnline);
    _wsService.on(WebSocketServerEvent.userOffline, _onUserOffline);

    // Listen for message edits and deletes
    _wsService.on(WebSocketServerEvent.messageEdited, _onMessageEdited);
    _wsService.on(WebSocketServerEvent.messageDeleted, _onMessageDeleted);

    // Listen for reactions
    _wsService.on(WebSocketServerEvent.reactionAdded, _onReactionAdded);
    _wsService.on(WebSocketServerEvent.reactionRemoved, _onReactionRemoved);

    debugPrint('🔌 _initWebSocket: All WebSocket listeners registered');
  }

  @override
  void dispose() {
    _wsService.off(WebSocketServerEvent.newMessage, _onNewMessage);
    _wsService.off(WebSocketServerEvent.messageStatus, _onMessageStatus);
    _wsService.off(WebSocketServerEvent.userOnline, _onUserOnline);
    _wsService.off(WebSocketServerEvent.userOffline, _onUserOffline);
    _wsService.off(WebSocketServerEvent.messageEdited, _onMessageEdited);
    _wsService.off(WebSocketServerEvent.messageDeleted, _onMessageDeleted);
    _wsService.off(WebSocketServerEvent.reactionAdded, _onReactionAdded);
    _wsService.off(WebSocketServerEvent.reactionRemoved, _onReactionRemoved);
    super.dispose();
  }

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

    updateMessageStatus(conversationId, messageIds, MessageStatus.fromString(status));
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

    if (conversationId == null || messageId == null || emoji == null || userId == null) return;

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
        state = AsyncValue.data([...current, ...conversationsResult.conversations]);
      }
      _offset += conversationsResult.conversations.length;
    } else {
      state = AsyncValue.error(result.error ?? 'Failed to load conversations', StackTrace.current);
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    await loadConversations();
  }

  Future<bool> sendMessage(String conversationId, String content, {String? replyToId}) async {
    final result = await _chatService.sendMessage(conversationId, content, replyToId: replyToId);

    if (result.success && result.data != null) {
      final message = result.data!;
      final conversations = state.valueOrNull ?? [];

      state = AsyncValue.data(conversations.map((conversation) {
        if (conversation.id == conversationId) {
          return conversation.copyWith(
            messages: [...conversation.messages, message],
            lastMessageAt: DateTime.now(),
          );
        }
        return conversation;
      }).toList());
      return true;
    }
    return false;
  }

  Future<bool> sendImageMessage(String conversationId, File image, {String? replyToId}) async {
    final result = await _chatService.sendImageMessage(conversationId, image, replyToId: replyToId);

    if (result.success && result.data != null) {
      final message = result.data!;
      final conversations = state.valueOrNull ?? [];

      state = AsyncValue.data(conversations.map((conversation) {
        if (conversation.id == conversationId) {
          return conversation.copyWith(
            messages: [...conversation.messages, message],
            lastMessageAt: DateTime.now(),
          );
        }
        return conversation;
      }).toList());
      return true;
    }
    return false;
  }

  Future<bool> sendVideoMessage(String conversationId, File video, {int? duration, String? replyToId}) async {
    final result = await _chatService.sendVideoMessage(conversationId, video, duration: duration, replyToId: replyToId);

    if (result.success && result.data != null) {
      final message = result.data!;
      final conversations = state.valueOrNull ?? [];

      state = AsyncValue.data(conversations.map((conversation) {
        if (conversation.id == conversationId) {
          return conversation.copyWith(
            messages: [...conversation.messages, message],
            lastMessageAt: DateTime.now(),
          );
        }
        return conversation;
      }).toList());
      return true;
    }
    return false;
  }

  Future<bool> sendVoiceMessage(String conversationId, File voice, {int? duration, String? replyToId}) async {
    final result = await _chatService.sendVoiceMessage(conversationId, voice, duration: duration, replyToId: replyToId);

    if (result.success && result.data != null) {
      final message = result.data!;
      final conversations = state.valueOrNull ?? [];

      state = AsyncValue.data(conversations.map((conversation) {
        if (conversation.id == conversationId) {
          return conversation.copyWith(
            messages: [...conversation.messages, message],
            lastMessageAt: DateTime.now(),
          );
        }
        return conversation;
      }).toList());
      return true;
    }
    return false;
  }

  Future<bool> sendStickerMessage(String conversationId, String stickerId, {String? replyToId}) async {
    final result = await _chatService.sendStickerMessage(conversationId, stickerId, replyToId: replyToId);

    if (result.success && result.data != null) {
      final message = result.data!;
      final conversations = state.valueOrNull ?? [];

      state = AsyncValue.data(conversations.map((conversation) {
        if (conversation.id == conversationId) {
          return conversation.copyWith(
            messages: [...conversation.messages, message],
            lastMessageAt: DateTime.now(),
          );
        }
        return conversation;
      }).toList());
      return true;
    }
    return false;
  }

  Future<bool> editMessage(String conversationId, String messageId, String newContent) async {
    final result = await _chatService.editMessage(conversationId, messageId, newContent);

    if (result.success && result.data != null) {
      _updateMessageInConversation(conversationId, result.data!);
      return true;
    }
    return false;
  }

  Future<bool> deleteMessage(String conversationId, String messageId, {bool forEveryone = false}) async {
    final result = await _chatService.deleteMessage(conversationId, messageId, forEveryone: forEveryone);

    if (result.success) {
      _deleteMessageFromConversation(conversationId, messageId);
      return true;
    }
    return false;
  }

  Future<bool> addReaction(String conversationId, String messageId, String emoji) async {
    final result = await _chatService.addReaction(conversationId, messageId, emoji);
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
      // Also send via WebSocket
      _wsService.sendMessageRead(conversationId, unreadMessageIds);

      state = AsyncValue.data(conversations.map((c) {
        if (c.id == conversationId) {
          return c.copyWith(
            unreadCount: 0,
            messages: c.messages.map((m) => m.copyWith(status: MessageStatus.read)).toList(),
          );
        }
        return c;
      }).toList());
      return true;
    }
    return false;
  }

  void addMessageToConversation(String conversationId, Message message) {
    final conversations = state.valueOrNull ?? [];
    state = AsyncValue.data(conversations.map((conversation) {
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
    }).toList());
  }

  void _updateMessageInConversation(String conversationId, Message updatedMessage) {
    final conversations = state.valueOrNull ?? [];
    state = AsyncValue.data(conversations.map((conversation) {
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
    }).toList());
  }

  void _deleteMessageFromConversation(String conversationId, String messageId) {
    final conversations = state.valueOrNull ?? [];
    state = AsyncValue.data(conversations.map((conversation) {
      if (conversation.id == conversationId) {
        return conversation.copyWith(
          messages: conversation.messages.where((m) => m.id != messageId).toList(),
        );
      }
      return conversation;
    }).toList());
  }

  void _addReactionToMessage(String conversationId, String messageId, String emoji, String userId) {
    final conversations = state.valueOrNull ?? [];
    state = AsyncValue.data(conversations.map((conversation) {
      if (conversation.id == conversationId) {
        return conversation.copyWith(
          messages: conversation.messages.map((m) {
            if (m.id == messageId) {
              // Remove any existing reaction from this user
              final filteredReactions = m.reactions.where((r) => r.userId != userId).toList();
              return m.copyWith(
                reactions: [
                  ...filteredReactions,
                  MessageReaction(emoji: emoji, userId: userId, createdAt: DateTime.now()),
                ],
              );
            }
            return m;
          }).toList(),
        );
      }
      return conversation;
    }).toList());
  }

  void _removeReactionFromMessage(String conversationId, String messageId, String userId) {
    final conversations = state.valueOrNull ?? [];
    state = AsyncValue.data(conversations.map((conversation) {
      if (conversation.id == conversationId) {
        return conversation.copyWith(
          messages: conversation.messages.map((m) {
            if (m.id == messageId) {
              return m.copyWith(
                reactions: m.reactions.where((r) => r.userId != userId).toList(),
              );
            }
            return m;
          }).toList(),
        );
      }
      return conversation;
    }).toList());
  }

  void updateMessageStatus(String conversationId, List<String> messageIds, MessageStatus status) {
    final conversations = state.valueOrNull ?? [];
    state = AsyncValue.data(conversations.map((conversation) {
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
    }).toList());
  }

  void updateUserOnlineStatus(String userId, bool isOnline) {
    final conversations = state.valueOrNull ?? [];
    state = AsyncValue.data(conversations.map((conversation) {
      if (conversation.otherUser.id == userId) {
        return conversation.copyWith(
          otherUser: conversation.otherUser.copyWith(isOnline: isOnline),
        );
      }
      return conversation;
    }).toList());
  }

  // Send typing indicator
  void sendTyping(String conversationId) {
    _wsService.sendTyping(conversationId);
  }

  // Send stop typing indicator
  void sendStopTyping(String conversationId) {
    _wsService.sendStopTyping(conversationId);
  }

  // Send recording voice indicator
  void sendRecordingVoice(String conversationId) {
    _wsService.sendRecordingVoice(conversationId);
  }
}

// Typing indicators provider
final typingUsersProvider = StateNotifierProvider<TypingUsersNotifier, Map<String, String?>>((ref) {
  final wsService = ref.watch(webSocketServiceProvider);
  return TypingUsersNotifier(wsService);
});

class TypingUsersNotifier extends StateNotifier<Map<String, String?>> {
  final WebSocketService _wsService;

  TypingUsersNotifier(this._wsService) : super({}) {
    _wsService.on(WebSocketServerEvent.userTyping, _onUserTyping);
    _wsService.on(WebSocketServerEvent.userStopTyping, _onUserStopTyping);
    _wsService.on(WebSocketServerEvent.userRecordingVoice, _onUserRecordingVoice);
  }

  @override
  void dispose() {
    _wsService.off(WebSocketServerEvent.userTyping, _onUserTyping);
    _wsService.off(WebSocketServerEvent.userStopTyping, _onUserStopTyping);
    _wsService.off(WebSocketServerEvent.userRecordingVoice, _onUserRecordingVoice);
    super.dispose();
  }

  void _onUserTyping(Map<String, dynamic> data) {
    final conversationId = data['conversation_id'] as String?;
    final userId = data['user_id'] as String?;
    if (conversationId != null && userId != null) {
      state = {...state, conversationId: userId};
    }
  }

  void _onUserStopTyping(Map<String, dynamic> data) {
    final conversationId = data['conversation_id'] as String?;
    if (conversationId != null) {
      state = {...state, conversationId: null};
    }
  }

  void _onUserRecordingVoice(Map<String, dynamic> data) {
    final conversationId = data['conversation_id'] as String?;
    final userId = data['user_id'] as String?;
    if (conversationId != null && userId != null) {
      // Store with a special marker for recording voice
      state = {...state, '${conversationId}_recording': userId};
    }
  }

  bool isTyping(String conversationId) => state[conversationId] != null;
  bool isRecordingVoice(String conversationId) => state['${conversationId}_recording'] != null;
}

// Messages provider for a specific conversation
final conversationMessagesProvider = FutureProvider.family<List<Message>, String>((ref, conversationId) async {
  final chatService = ref.watch(chatServiceProvider);
  final result = await chatService.getMessages(conversationId);

  if (result.success && result.data != null) {
    return result.data!.messages;
  }
  throw Exception(result.error ?? 'Failed to load messages');
});

final selectedConversationProvider = StateProvider<Conversation?>((ref) => null);

final unreadMessagesCountProvider = Provider<int>((ref) {
  final conversationsState = ref.watch(conversationsProvider);
  return conversationsState.maybeWhen(
    data: (conversations) => conversations.fold(0, (sum, c) => sum + c.unreadCount),
    orElse: () => 0,
  );
});

// WebSocket connection status
final webSocketConnectedProvider = Provider<bool>((ref) {
  final wsService = ref.watch(webSocketServiceProvider);
  return wsService.isConnected;
});

// Reply to message provider - tracks which message is being replied to
final replyToMessageProvider = StateProvider<Message?>((ref) => null);
