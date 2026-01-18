class Message {
  final String id;
  final String senderId;
  final String? receiverId;
  final String content;
  final DateTime timestamp;
  final MessageStatus status;
  final MessageType type;

  const Message({
    required this.id,
    required this.senderId,
    this.receiverId,
    required this.content,
    required this.timestamp,
    this.status = MessageStatus.sent,
    this.type = MessageType.text,
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
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      type: type ?? this.type,
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
  gif;

  String toApiString() {
    return name;
  }

  static MessageType fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'text':
        return MessageType.text;
      case 'image':
        return MessageType.image;
      case 'gif':
        return MessageType.gif;
      default:
        return MessageType.text;
    }
  }
}
