import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'constants.dart';
import 'providers.dart';

class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String type;
  final String content;
  final Map<String, dynamic>? media;
  final String? clientMessageId;
  final DateTime serverTimestamp;
  final String? replyToMessageId;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.content,
    this.media,
    this.clientMessageId,
    required this.serverTimestamp,
    this.replyToMessageId,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        conversationId: j['conversation_id'] as String,
        senderId: j['sender_id'] as String,
        type: j['type'] as String? ?? 'text',
        content: j['content'] as String? ?? '',
        media: (j['media'] as Map?)?.cast<String, dynamic>(),
        clientMessageId: j['client_message_id'] as String?,
        serverTimestamp: j['server_timestamp'] is String
            ? DateTime.parse(j['server_timestamp'])
            : DateTime.now(),
        replyToMessageId: j['reply_to_message_id'] as String?,
      );
}

final messagesProvider = StateNotifierProvider.family<MessagesNotifier,
    List<ChatMessage>, String>((ref, conversationId) {
  return MessagesNotifier(ref, conversationId);
});

class MessagesNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref ref;
  final String conversationId;
  MessagesNotifier(this.ref, this.conversationId) : super(const []) {
    _wireSocket();
  }

  void _wireSocket() {
    final socket = ref.read(socketClientProvider);
    socket.eventStream.listen((tuple) {
      final event = tuple.$1;
      final data = tuple.$2;
      if (data is! Map) return;
      switch (event) {
        case RtEvents.messageNew:
        case RtEvents.messageSent:
          final msg = data['message'];
          if (msg is Map<String, dynamic> &&
              msg['conversation_id'] == conversationId) {
            _upsert(ChatMessage.fromJson(msg));
          }
          break;
        case RtEvents.messageDeleted:
          if (data['conversation_id'] == conversationId) {
            final id = data['message_id'];
            state = state.where((m) => m.id != id).toList();
          }
          break;
      }
    });
  }

  void _upsert(ChatMessage m) {
    final byCmid = state.indexWhere((x) =>
        x.clientMessageId != null && x.clientMessageId == m.clientMessageId);
    if (byCmid >= 0) {
      final next = [...state];
      next[byCmid] = m;
      state = next;
      return;
    }
    if (state.any((x) => x.id == m.id)) return;
    state = [...state, m]
      ..sort((a, b) => a.serverTimestamp.compareTo(b.serverTimestamp));
  }

  void seed(List<ChatMessage> initial) {
    state = [...initial]
      ..sort((a, b) => a.serverTimestamp.compareTo(b.serverTimestamp));
  }
}
