import 'dart:convert';

enum OutboxStatus { pending, sending, sent, failed }

class OutboxEntry {
  final String clientMessageId;
  final String conversationId;
  final String type;
  final String content;
  final Map<String, dynamic>? media;
  final String? replyToMessageId;
  final OutboxStatus status;
  final int attempts;
  final String? errorCode;
  final DateTime createdAt;
  final String? canonicalMessageId;

  const OutboxEntry({
    required this.clientMessageId,
    required this.conversationId,
    required this.type,
    required this.content,
    this.media,
    this.replyToMessageId,
    this.status = OutboxStatus.pending,
    this.attempts = 0,
    this.errorCode,
    required this.createdAt,
    this.canonicalMessageId,
  });

  OutboxEntry copy({OutboxStatus? status, int? attempts, String? errorCode, String? canonicalMessageId}) =>
      OutboxEntry(
        clientMessageId: clientMessageId,
        conversationId: conversationId,
        type: type,
        content: content,
        media: media,
        replyToMessageId: replyToMessageId,
        status: status ?? this.status,
        attempts: attempts ?? this.attempts,
        errorCode: errorCode ?? this.errorCode,
        createdAt: createdAt,
        canonicalMessageId: canonicalMessageId ?? this.canonicalMessageId,
      );

  Map<String, dynamic> toJson() => {
    'cmid': clientMessageId,
    'cid': conversationId,
    'type': type,
    'content': content,
    'media': media,
    'replyTo': replyToMessageId,
    'status': status.name,
    'attempts': attempts,
    'errorCode': errorCode,
    'createdAt': createdAt.toIso8601String(),
    'canonical': canonicalMessageId,
  };

  static OutboxEntry fromJson(Map<String, dynamic> j) => OutboxEntry(
    clientMessageId: j['cmid'],
    conversationId: j['cid'],
    type: j['type'],
    content: j['content'],
    media: (j['media'] as Map?)?.cast<String, dynamic>(),
    replyToMessageId: j['replyTo'],
    status: OutboxStatus.values.byName(j['status']),
    attempts: j['attempts'] ?? 0,
    errorCode: j['errorCode'],
    createdAt: DateTime.parse(j['createdAt']),
    canonicalMessageId: j['canonical'],
  );

  String encode() => jsonEncode(toJson());
  static OutboxEntry decode(String s) => fromJson(jsonDecode(s));
}
