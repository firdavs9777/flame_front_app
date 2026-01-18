import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/chat_service.dart';

final chatServiceProvider = Provider<ChatService>((ref) => ChatService());

// Conversations provider with async loading from API
final conversationsProvider = StateNotifierProvider<ConversationsNotifier, AsyncValue<List<Conversation>>>((ref) {
  return ConversationsNotifier(ref.watch(chatServiceProvider));
});

class ConversationsNotifier extends StateNotifier<AsyncValue<List<Conversation>>> {
  final ChatService _chatService;
  bool _hasMore = true;
  int _offset = 0;
  static const int _limit = 20;

  ConversationsNotifier(this._chatService) : super(const AsyncValue.loading());

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

  Future<bool> sendMessage(String conversationId, String content) async {
    final result = await _chatService.sendMessage(conversationId, content);

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

  Future<bool> sendImageMessage(String conversationId, File image) async {
    final result = await _chatService.sendImageMessage(conversationId, image);

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
        return conversation.copyWith(
          messages: [...conversation.messages, message],
          lastMessageAt: message.timestamp,
          unreadCount: conversation.unreadCount + 1,
        );
      }
      return conversation;
    }).toList());
  }
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
