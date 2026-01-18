import 'dart:io';
import 'package:flame/models/message.dart';
import 'package:flame/models/conversation.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/user_service.dart';

class ChatService {
  final ApiClient _apiClient = ApiClient();

  // Get all conversations
  Future<ServiceResult<ConversationsResult>> getConversations({
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _apiClient.get(
      '/conversations',
      queryParams: {
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );

    if (response.success && response.data != null) {
      final conversationsData = response.data['conversations'] as List? ?? [];
      final conversations = conversationsData
          .map((c) => Conversation.fromJson(c))
          .toList();

      final pagination = response.data['pagination'] as Map<String, dynamic>? ?? {};

      return ServiceResult.success(ConversationsResult(
        conversations: conversations,
        total: pagination['total'] ?? conversations.length,
        limit: pagination['limit'] ?? limit,
        offset: pagination['offset'] ?? offset,
        hasMore: pagination['has_more'] ?? false,
      ));
    }

    return ServiceResult.failure(response.error ?? 'Failed to get conversations');
  }

  // Get messages in a conversation
  Future<ServiceResult<MessagesResult>> getMessages(
    String conversationId, {
    int limit = 50,
    String? before,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
    };
    if (before != null) {
      queryParams['before'] = before;
    }

    final response = await _apiClient.get(
      '/conversations/$conversationId/messages',
      queryParams: queryParams,
    );

    if (response.success && response.data != null) {
      final messagesData = response.data['messages'] as List? ?? [];
      final messages = messagesData.map((m) => Message.fromJson(m)).toList();

      return ServiceResult.success(MessagesResult(
        messages: messages,
        hasMore: response.data['has_more'] ?? false,
      ));
    }

    return ServiceResult.failure(response.error ?? 'Failed to get messages');
  }

  // Send a text message
  Future<ServiceResult<Message>> sendMessage(
    String conversationId,
    String content, {
    MessageType type = MessageType.text,
  }) async {
    final response = await _apiClient.post(
      '/conversations/$conversationId/messages',
      body: {
        'content': content,
        'type': type.toApiString(),
      },
    );

    if (response.success && response.data != null) {
      return ServiceResult.success(Message.fromJson(response.data));
    }

    return ServiceResult.failure(response.error ?? 'Failed to send message');
  }

  // Send an image message
  Future<ServiceResult<Message>> sendImageMessage(
    String conversationId,
    File image,
  ) async {
    final response = await _apiClient.uploadFile(
      '/conversations/$conversationId/messages/image',
      image,
      fieldName: 'image',
    );

    if (response.success && response.data != null) {
      return ServiceResult.success(Message.fromJson(response.data));
    }

    return ServiceResult.failure(response.error ?? 'Failed to send image');
  }

  // Mark messages as read
  Future<ServiceResult<void>> markMessagesAsRead(
    String conversationId,
    List<String> messageIds,
  ) async {
    final response = await _apiClient.post(
      '/conversations/$conversationId/read',
      body: {
        'message_ids': messageIds,
      },
    );

    if (response.success) {
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to mark messages as read');
  }
}

class ConversationsResult {
  final List<Conversation> conversations;
  final int total;
  final int limit;
  final int offset;
  final bool hasMore;

  ConversationsResult({
    required this.conversations,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });
}

class MessagesResult {
  final List<Message> messages;
  final bool hasMore;

  MessagesResult({
    required this.messages,
    required this.hasMore,
  });
}
