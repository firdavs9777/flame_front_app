class Message {
  final String id;
  final String senderId;
  final String? receiverId;
  final String content;
  final DateTime timestamp;
  final MessageStatus status;
  final MessageType type;
  final bool isEdited;
  final bool isDeleted;
  final List<MessageReaction> reactions;
  final ReplyTo? replyTo;
  final String? imageUrl;
  final String? videoUrl;
  final String? audioUrl;
  final MediaInfo? mediaInfo;

  const Message({
    required this.id,
    required this.senderId,
    this.receiverId,
    required this.content,
    required this.timestamp,
    this.status = MessageStatus.sent,
    this.type = MessageType.text,
    this.isEdited = false,
    this.isDeleted = false,
    this.reactions = const [],
    this.replyTo,
    this.imageUrl,
    this.videoUrl,
    this.audioUrl,
    this.mediaInfo,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? '',
      senderId: json['sender_id'] ?? '',
      receiverId: json['receiver_id'],
      content: json['content'] ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      status: MessageStatus.fromString(json['status']),
      type: MessageType.fromString(json['type']),
      isEdited: json['is_edited'] ?? false,
      isDeleted: json['is_deleted'] ?? false,
      reactions: (json['reactions'] as List?)
              ?.map((r) => MessageReaction.fromJson(r))
              .toList() ??
          [],
      replyTo: json['reply_to'] != null
          ? ReplyTo.fromJson(json['reply_to'])
          : null,
      imageUrl: json['image_url'],
      videoUrl: json['video_url'],
      audioUrl: json['audio_url'],
      mediaInfo: json['media_info'] != null
          ? MediaInfo.fromJson(json['media_info'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'status': status.toApiString(),
      'type': type.toApiString(),
      'is_edited': isEdited,
      'is_deleted': isDeleted,
      'reactions': reactions.map((r) => r.toJson()).toList(),
      'reply_to': replyTo?.toJson(),
      'image_url': imageUrl,
      'video_url': videoUrl,
      'audio_url': audioUrl,
      'media_info': mediaInfo?.toJson(),
    };
  }

  Message copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? content,
    DateTime? timestamp,
    MessageStatus? status,
    MessageType? type,
    bool? isEdited,
    bool? isDeleted,
    List<MessageReaction>? reactions,
    ReplyTo? replyTo,
    String? imageUrl,
    String? videoUrl,
    String? audioUrl,
    MediaInfo? mediaInfo,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      type: type ?? this.type,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      reactions: reactions ?? this.reactions,
      replyTo: replyTo ?? this.replyTo,
      imageUrl: imageUrl ?? this.imageUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      audioUrl: audioUrl ?? this.audioUrl,
      mediaInfo: mediaInfo ?? this.mediaInfo,
    );
  }

  bool isSentBy(String userId) => senderId == userId;

  String get timeText {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${timestamp.day}/${timestamp.month}';
  }

  /// Get the appropriate media URL based on message type
  String? get mediaUrl {
    switch (type) {
      case MessageType.image:
        return imageUrl ?? content;
      case MessageType.video:
        return videoUrl ?? content;
      case MessageType.audio:
      case MessageType.voice:
        return audioUrl ?? content;
      case MessageType.sticker:
        return content;
      default:
        return null;
    }
  }
}

class MessageReaction {
  final String emoji;
  final String userId;
  final DateTime createdAt;

  const MessageReaction({
    required this.emoji,
    required this.userId,
    required this.createdAt,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      emoji: json['emoji'] ?? '',
      userId: json['user_id'] ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'emoji': emoji,
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class ReplyTo {
  final String messageId;
  final String senderId;
  final String senderName;
  final String content;
  final MessageType type;

  const ReplyTo({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.type,
  });

  factory ReplyTo.fromJson(Map<String, dynamic> json) {
    return ReplyTo(
      messageId: json['message_id'] ?? '',
      senderId: json['sender_id'] ?? '',
      senderName: json['sender_name'] ?? '',
      content: json['content'] ?? '',
      type: MessageType.fromString(json['type']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'sender_id': senderId,
      'sender_name': senderName,
      'content': content,
      'type': type.toApiString(),
    };
  }
}

class MediaInfo {
  final int? duration;
  final int? width;
  final int? height;
  final String? thumbnailUrl;
  final int? fileSize;
  final String? mimeType;

  const MediaInfo({
    this.duration,
    this.width,
    this.height,
    this.thumbnailUrl,
    this.fileSize,
    this.mimeType,
  });

  factory MediaInfo.fromJson(Map<String, dynamic> json) {
    return MediaInfo(
      duration: json['duration'],
      width: json['width'],
      height: json['height'],
      thumbnailUrl: json['thumbnail_url'],
      fileSize: json['file_size'],
      mimeType: json['mime_type'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'duration': duration,
      'width': width,
      'height': height,
      'thumbnail_url': thumbnailUrl,
      'file_size': fileSize,
      'mime_type': mimeType,
    };
  }
}

enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed;

  String toApiString() {
    return name;
  }

  static MessageStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'sending':
        return MessageStatus.sending;
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      case 'failed':
        return MessageStatus.failed;
      default:
        return MessageStatus.sent;
    }
  }
}

enum MessageType {
  text,
  image,
  video,
  audio,
  voice,
  gif,
  sticker,
  file;

  String toApiString() {
    return name;
  }

  static MessageType fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'text':
        return MessageType.text;
      case 'image':
        return MessageType.image;
      case 'video':
        return MessageType.video;
      case 'audio':
        return MessageType.audio;
      case 'voice':
        return MessageType.voice;
      case 'gif':
        return MessageType.gif;
      case 'sticker':
        return MessageType.sticker;
      case 'file':
        return MessageType.file;
      default:
        return MessageType.text;
    }
  }

  bool get isMedia => this == image || this == video || this == audio || this == voice || this == gif || this == sticker;
}
