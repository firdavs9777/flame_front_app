import 'package:flame/models/message.dart';
import 'package:flame/models/user.dart';

class Conversation {
  final String id;
  final String? matchId;
  final User otherUser;

  /// The newest message, or null for a conversation nobody has written in.
  ///
  /// This used to be a `List<Message>` holding the whole thread, with
  /// `lastMessage` as a getter over it. Nothing on the conversation-list
  /// surface ever read another element, while `addMessageToConversation`
  /// appended to it on every socket push, for every conversation, for the whole
  /// session, with nothing trimming it — and `markAsRead` mapped a `copyWith`
  /// over all of it to set a status only the newest element displays.
  ///
  /// The open thread is owned by `messageThreadProvider`.
  final Message? lastMessage;

  final DateTime lastMessageAt;
  final int unreadCount;

  /// Whether the CURRENT user has muted this conversation. Muting is per
  /// participant, so this is the viewer's state, not a property of the chat.
  /// Defaults false: an older backend omits it, and a conversation that
  /// silently read as muted would suppress notifications with nothing on
  /// screen explaining why.
  final bool isMuted;

  const Conversation({
    required this.id,
    this.matchId,
    required this.otherUser,
    this.lastMessage,
    required this.lastMessageAt,
    this.unreadCount = 0,
    this.isMuted = false,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    // `last_message` is what the list endpoint sends, and it wins: it is the
    // field the server computes for exactly this purpose.
    //
    // The `messages` array is a legacy shape no current endpoint produces — the
    // thread endpoint's messages are parsed by `MessagesResult`, not here. It is
    // still read so an older payload degrades rather than losing its preview,
    // and its last element is treated as the newest, which is the ordering the
    // previous `messages.last` getter assumed.
    Message? lastMessage;
    final rawMessages = json['messages'];
    if (json['last_message'] != null) {
      lastMessage = Message.fromJson(json['last_message']);
    } else if (rawMessages is List && rawMessages.isNotEmpty) {
      lastMessage = Message.fromJson(rawMessages.last);
    }

    return Conversation(
      id: json['id'] ?? '',
      matchId: json['match_id'],
      otherUser: User.fromJson(json['other_user'] ?? {}),
      lastMessage: lastMessage,
      lastMessageAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : (json['last_message_at'] != null
              ? DateTime.parse(json['last_message_at'])
              : DateTime.now()),
      unreadCount: json['unread_count'] ?? 0,
      isMuted: json['is_muted'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'match_id': matchId,
      'other_user': otherUser.toJson(),
      'last_message': lastMessage?.toJson(),
      'last_message_at': lastMessageAt.toIso8601String(),
      'unread_count': unreadCount,
      'is_muted': isMuted,
    };
  }

  Conversation copyWith({
    String? id,
    String? matchId,
    User? otherUser,
    Message? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
    bool? isMuted,
  }) {
    return Conversation(
      id: id ?? this.id,
      matchId: matchId ?? this.matchId,
      otherUser: otherUser ?? this.otherUser,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isMuted: isMuted ?? this.isMuted,
    );
  }

  String get lastMessagePreview {
    final msg = lastMessage;
    if (msg == null) return 'Say hello!';
    if (msg.type == MessageType.image) return '📷 Photo';
    if (msg.type == MessageType.gif) return 'GIF';
    if (msg.content.length > 40) {
      return '${msg.content.substring(0, 40)}...';
    }
    return msg.content;
  }

  bool get hasUnread => unreadCount > 0;
}
