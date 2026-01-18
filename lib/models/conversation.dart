import 'package:flame/models/message.dart';
import 'package:flame/models/user.dart';

class Conversation {
  final String id;
  final String? matchId;
  final User otherUser;
  final List<Message> messages;
  final DateTime lastMessageAt;
  final int unreadCount;

  const Conversation({
    required this.id,
    this.matchId,
    required this.otherUser,
    required this.messages,
    required this.lastMessageAt,
    this.unreadCount = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    // Parse messages if present
    List<Message> messages = [];
    if (json['messages'] != null) {
      messages = (json['messages'] as List)
          .map((m) => Message.fromJson(m))
          .toList();
    }

    // Parse last_message if present (for conversation list)
    Message? lastMessage;
    if (json['last_message'] != null) {
      lastMessage = Message.fromJson(json['last_message']);
      // Add to messages list if not already there
      if (messages.isEmpty ||
          (messages.isNotEmpty && messages.last.id != lastMessage.id)) {
        messages = [...messages, lastMessage];
      }
    }

    return Conversation(
      id: json['id'] ?? '',
      matchId: json['match_id'],
      otherUser: User.fromJson(json['other_user'] ?? {}),
      messages: messages,
      lastMessageAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : (json['last_message_at'] != null
              ? DateTime.parse(json['last_message_at'])
              : DateTime.now()),
      unreadCount: json['unread_count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'match_id': matchId,
      'other_user': otherUser.toJson(),
      'messages': messages.map((m) => m.toJson()).toList(),
      'last_message_at': lastMessageAt.toIso8601String(),
      'unread_count': unreadCount,
    };
  }

  Conversation copyWith({
    String? id,
    String? matchId,
    User? otherUser,
    List<Message>? messages,
    DateTime? lastMessageAt,
    int? unreadCount,
  }) {
    return Conversation(
      id: id ?? this.id,
      matchId: matchId ?? this.matchId,
      otherUser: otherUser ?? this.otherUser,
      messages: messages ?? this.messages,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }

  Message? get lastMessage => messages.isNotEmpty ? messages.last : null;

  String get lastMessagePreview {
    if (lastMessage == null) return 'Say hello!';
    final msg = lastMessage!;
    if (msg.type == MessageType.image) return '📷 Photo';
    if (msg.type == MessageType.gif) return 'GIF';
    if (msg.content.length > 40) {
      return '${msg.content.substring(0, 40)}...';
    }
    return msg.content;
  }

  bool get hasUnread => unreadCount > 0;
}
