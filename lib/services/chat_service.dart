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
    String? replyToId,
  }) async {
    final body = <String, dynamic>{
      'content': content,
      'type': type.toApiString(),
    };
    if (replyToId != null) {
      body['reply_to_id'] = replyToId;
    }

    final response = await _apiClient.post(
      '/conversations/$conversationId/messages',
      body: body,
    );

    if (response.success && response.data != null) {
      return ServiceResult.success(Message.fromJson(response.data));
    }

    return ServiceResult.failure(response.error ?? 'Failed to send message');
  }

  // Send an image message
  Future<ServiceResult<Message>> sendImageMessage(
    String conversationId,
    File image, {
    String? replyToId,
  }) async {
    final fields = <String, String>{};
    if (replyToId != null) {
      fields['reply_to_id'] = replyToId;
    }

    final response = await _apiClient.uploadFile(
      '/conversations/$conversationId/messages/image',
      image,
      fieldName: 'image',
      fields: fields.isNotEmpty ? fields : null,
    );

    if (response.success && response.data != null) {
      return ServiceResult.success(Message.fromJson(response.data));
    }

    return ServiceResult.failure(response.error ?? 'Failed to send image');
  }

  // Send a video message
  Future<ServiceResult<Message>> sendVideoMessage(
    String conversationId,
    File video, {
    File? thumbnail,
    int? duration,
    int? width,
    int? height,
    String? replyToId,
  }) async {
    final fields = <String, String>{};
    if (duration != null) fields['duration'] = duration.toString();
    if (width != null) fields['width'] = width.toString();
    if (height != null) fields['height'] = height.toString();
    if (replyToId != null) fields['reply_to_id'] = replyToId;

    final response = await _apiClient.uploadFile(
      '/conversations/$conversationId/messages/video',
      video,
      fieldName: 'video',
      fields: fields.isNotEmpty ? fields : null,
    );

    if (response.success && response.data != null) {
      return ServiceResult.success(Message.fromJson(response.data));
    }

    return ServiceResult.failure(response.error ?? 'Failed to send video');
  }

  // Send an audio message
  Future<ServiceResult<Message>> sendAudioMessage(
    String conversationId,
    File audio, {
    int? duration,
    String? replyToId,
  }) async {
    final fields = <String, String>{};
    if (duration != null) fields['duration'] = duration.toString();
    if (replyToId != null) fields['reply_to_id'] = replyToId;

    final response = await _apiClient.uploadFile(
      '/conversations/$conversationId/messages/audio',
      audio,
      fieldName: 'audio',
      fields: fields.isNotEmpty ? fields : null,
    );

    if (response.success && response.data != null) {
      return ServiceResult.success(Message.fromJson(response.data));
    }

    return ServiceResult.failure(response.error ?? 'Failed to send audio');
  }

  // Send a voice message
  Future<ServiceResult<Message>> sendVoiceMessage(
    String conversationId,
    File voice, {
    int? duration,
    String? replyToId,
  }) async {
    final fields = <String, String>{};
    if (duration != null) fields['duration'] = duration.toString();
    if (replyToId != null) fields['reply_to_id'] = replyToId;

    final response = await _apiClient.uploadFile(
      '/conversations/$conversationId/messages/voice',
      voice,
      fieldName: 'voice',
      fields: fields.isNotEmpty ? fields : null,
    );

    if (response.success && response.data != null) {
      return ServiceResult.success(Message.fromJson(response.data));
    }

    return ServiceResult.failure(response.error ?? 'Failed to send voice message');
  }

  // Send a sticker message
  Future<ServiceResult<Message>> sendStickerMessage(
    String conversationId,
    String stickerId, {
    String? replyToId,
  }) async {
    final body = <String, dynamic>{
      'sticker_id': stickerId,
    };
    if (replyToId != null) {
      body['reply_to_id'] = replyToId;
    }

    final response = await _apiClient.post(
      '/conversations/$conversationId/messages/sticker',
      body: body,
    );

    if (response.success && response.data != null) {
      return ServiceResult.success(Message.fromJson(response.data));
    }

    return ServiceResult.failure(response.error ?? 'Failed to send sticker');
  }

  // Edit a message
  Future<ServiceResult<Message>> editMessage(
    String conversationId,
    String messageId,
    String newContent,
  ) async {
    final response = await _apiClient.patch(
      '/conversations/$conversationId/messages/$messageId',
      body: {
        'content': newContent,
      },
    );

    if (response.success && response.data != null) {
      return ServiceResult.success(Message.fromJson(response.data));
    }

    return ServiceResult.failure(response.error ?? 'Failed to edit message');
  }

  // Delete a message
  Future<ServiceResult<void>> deleteMessage(
    String conversationId,
    String messageId, {
    bool forEveryone = false,
  }) async {
    final response = await _apiClient.delete(
      '/conversations/$conversationId/messages/$messageId',
      queryParams: {
        'for_everyone': forEveryone.toString(),
      },
    );

    if (response.success) {
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to delete message');
  }

  // Add reaction to a message
  Future<ServiceResult<List<MessageReaction>>> addReaction(
    String conversationId,
    String messageId,
    String emoji,
  ) async {
    final response = await _apiClient.post(
      '/conversations/$conversationId/messages/$messageId/reactions',
      body: {
        'emoji': emoji,
      },
    );

    if (response.success && response.data != null) {
      final reactionsData = response.data['reactions'] as List? ?? [];
      final reactions = reactionsData
          .map((r) => MessageReaction.fromJson(r))
          .toList();
      return ServiceResult.success(reactions);
    }

    return ServiceResult.failure(response.error ?? 'Failed to add reaction');
  }

  // Remove reaction from a message
  Future<ServiceResult<void>> removeReaction(
    String conversationId,
    String messageId,
  ) async {
    final response = await _apiClient.delete(
      '/conversations/$conversationId/messages/$messageId/reactions',
    );

    if (response.success) {
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to remove reaction');
  }

  // Pin a message
  Future<ServiceResult<List<PinnedMessage>>> pinMessage(
    String conversationId,
    String messageId,
  ) async {
    final response = await _apiClient.post(
      '/conversations/$conversationId/pin',
      body: {
        'message_id': messageId,
      },
    );

    if (response.success && response.data != null) {
      final pinnedData = response.data['pinned_messages'] as List? ?? [];
      final pinnedMessages = pinnedData
          .map((p) => PinnedMessage.fromJson(p))
          .toList();
      return ServiceResult.success(pinnedMessages);
    }

    return ServiceResult.failure(response.error ?? 'Failed to pin message');
  }

  // Unpin a message
  Future<ServiceResult<void>> unpinMessage(
    String conversationId,
    String messageId,
  ) async {
    final response = await _apiClient.delete(
      '/conversations/$conversationId/pin/$messageId',
    );

    if (response.success) {
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to unpin message');
  }

  // Mute a conversation
  Future<ServiceResult<void>> muteConversation(
    String conversationId, {
    int? durationHours,
  }) async {
    final response = await _apiClient.post(
      '/conversations/$conversationId/mute',
      body: {
        'duration_hours': durationHours,
      },
    );

    if (response.success) {
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to mute conversation');
  }

  // Unmute a conversation
  Future<ServiceResult<void>> unmuteConversation(String conversationId) async {
    final response = await _apiClient.post(
      '/conversations/$conversationId/mute',
      body: {
        'duration_hours': 0,
      },
    );

    if (response.success) {
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to unmute conversation');
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

  // ===== Sticker APIs =====

  // Get all sticker packs
  Future<ServiceResult<List<StickerPack>>> getStickerPacks() async {
    final response = await _apiClient.get('/stickers/packs');

    if (response.success && response.data != null) {
      final packsData = response.data['packs'] as List? ?? [];
      final packs = packsData.map((p) => StickerPack.fromJson(p)).toList();
      return ServiceResult.success(packs);
    }

    return ServiceResult.failure(response.error ?? 'Failed to get sticker packs');
  }

  // Get sticker pack details with stickers
  Future<ServiceResult<StickerPackDetails>> getStickerPackDetails(String packId) async {
    final response = await _apiClient.get('/stickers/packs/$packId');

    if (response.success && response.data != null) {
      return ServiceResult.success(StickerPackDetails.fromJson(response.data));
    }

    return ServiceResult.failure(response.error ?? 'Failed to get sticker pack');
  }

  // Get my sticker packs
  Future<ServiceResult<List<StickerPack>>> getMyStickerPacks() async {
    final response = await _apiClient.get('/stickers/my-packs');

    if (response.success && response.data != null) {
      final packsData = response.data['packs'] as List? ?? [];
      final packs = packsData.map((p) => StickerPack.fromJson(p)).toList();
      return ServiceResult.success(packs);
    }

    return ServiceResult.failure(response.error ?? 'Failed to get my sticker packs');
  }

  // Add sticker pack
  Future<ServiceResult<void>> addStickerPack(String packId) async {
    final response = await _apiClient.post('/stickers/my-packs/$packId');

    if (response.success) {
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to add sticker pack');
  }

  // Remove sticker pack
  Future<ServiceResult<void>> removeStickerPack(String packId) async {
    final response = await _apiClient.delete('/stickers/my-packs/$packId');

    if (response.success) {
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to remove sticker pack');
  }

  // Get recent stickers
  Future<ServiceResult<List<Sticker>>> getRecentStickers({int limit = 20}) async {
    final response = await _apiClient.get(
      '/stickers/recent',
      queryParams: {'limit': limit.toString()},
    );

    if (response.success && response.data != null) {
      final stickersData = response.data['stickers'] as List? ?? [];
      final stickers = stickersData.map((s) => Sticker.fromJson(s)).toList();
      return ServiceResult.success(stickers);
    }

    return ServiceResult.failure(response.error ?? 'Failed to get recent stickers');
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

class PinnedMessage {
  final String messageId;
  final String content;
  final String pinnedBy;
  final DateTime pinnedAt;

  PinnedMessage({
    required this.messageId,
    required this.content,
    required this.pinnedBy,
    required this.pinnedAt,
  });

  factory PinnedMessage.fromJson(Map<String, dynamic> json) {
    return PinnedMessage(
      messageId: json['message_id'] ?? '',
      content: json['content'] ?? '',
      pinnedBy: json['pinned_by'] ?? '',
      pinnedAt: json['pinned_at'] != null
          ? DateTime.parse(json['pinned_at'])
          : DateTime.now(),
    );
  }
}

class StickerPack {
  final String id;
  final String name;
  final String description;
  final String thumbnailUrl;
  final String author;
  final bool isOfficial;
  final bool isPremium;
  final int stickerCount;

  StickerPack({
    required this.id,
    required this.name,
    required this.description,
    required this.thumbnailUrl,
    required this.author,
    required this.isOfficial,
    required this.isPremium,
    required this.stickerCount,
  });

  factory StickerPack.fromJson(Map<String, dynamic> json) {
    return StickerPack(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      thumbnailUrl: json['thumbnail_url'] ?? '',
      author: json['author'] ?? '',
      isOfficial: json['is_official'] ?? false,
      isPremium: json['is_premium'] ?? false,
      stickerCount: json['sticker_count'] ?? 0,
    );
  }
}

class StickerPackDetails {
  final StickerPack pack;
  final List<Sticker> stickers;

  StickerPackDetails({
    required this.pack,
    required this.stickers,
  });

  factory StickerPackDetails.fromJson(Map<String, dynamic> json) {
    return StickerPackDetails(
      pack: StickerPack.fromJson(json['pack'] ?? {}),
      stickers: (json['stickers'] as List? ?? [])
          .map((s) => Sticker.fromJson(s))
          .toList(),
    );
  }
}

class Sticker {
  final String id;
  final String emoji;
  final String imageUrl;
  final String thumbnailUrl;

  Sticker({
    required this.id,
    required this.emoji,
    required this.imageUrl,
    required this.thumbnailUrl,
  });

  factory Sticker.fromJson(Map<String, dynamic> json) {
    return Sticker(
      id: json['id'] ?? '',
      emoji: json['emoji'] ?? '',
      imageUrl: json['image_url'] ?? '',
      thumbnailUrl: json['thumbnail_url'] ?? '',
    );
  }
}
