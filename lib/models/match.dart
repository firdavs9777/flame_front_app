import 'package:flame/models/user.dart';
import 'package:flame/models/message.dart';

class Match {
  final String id;
  final User user;
  final DateTime matchedAt;
  final bool isNew;
  final Message? lastMessage;

  const Match({
    required this.id,
    required this.user,
    required this.matchedAt,
    this.isNew = true,
    this.lastMessage,
  });

  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      id: json['id'] ?? '',
      user: User.fromJson(json['user'] ?? {}),
      matchedAt: json['matched_at'] != null
          ? DateTime.parse(json['matched_at'])
          : DateTime.now(),
      isNew: json['is_new'] ?? true,
      lastMessage: json['last_message'] != null
          ? Message.fromJson(json['last_message'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user': user.toJson(),
      'matched_at': matchedAt.toIso8601String(),
      'is_new': isNew,
      'last_message': lastMessage?.toJson(),
    };
  }

  Match copyWith({
    String? id,
    User? user,
    DateTime? matchedAt,
    bool? isNew,
    Message? lastMessage,
  }) {
    return Match(
      id: id ?? this.id,
      user: user ?? this.user,
      matchedAt: matchedAt ?? this.matchedAt,
      isNew: isNew ?? this.isNew,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }
}
