import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/chat_provider.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

class _CountingChatService extends ChatService {
  int markCalls = 0;
  bool fail = false;

  @override
  Future<ServiceResult<void>> markMessagesAsRead(String conversationId) async {
    markCalls++;
    if (fail) return ServiceResult.failure('offline');
    return ServiceResult.success(null);
  }
}

class _Seeded extends ConversationsNotifier {
  _Seeded(ChatService service, List<Conversation> initial) : super(service) {
    state = AsyncValue.data(initial);
  }
}

/// `read: true` makes Message.fromJson give the message MessageStatus.read,
/// which is exactly the local state that used to suppress the server call.
Conversation _conv({required bool alreadyRead, int unread = 3}) =>
    Conversation.fromJson({
      'id': 'c1',
      'other_user': {'id': 'u2', 'name': 'B', 'photos': []},
      'unread_count': unread,
      'last_message': {
        'id': 'm1',
        'sender_id': 'u2',
        'text': 'hi',
        'created_at': '2026-08-18T00:00:00.000Z',
        'read': alreadyRead,
      },
      'updated_at': '2026-08-18T00:00:00.000Z',
    });

void main() {
  test('calls the server even when local state already looks read', () async {
    final service = _CountingChatService();
    final notifier = _Seeded(service, [_conv(alreadyRead: true)]);

    final ok = await notifier.markAsRead('c1');

    expect(ok, isTrue);
    expect(service.markCalls, 1,
        reason: 'a read receipt from the partner must not suppress our own');
    expect(notifier.state.value!.single.unreadCount, 0);
  });

  test('calls the server when local state looks unread', () async {
    final service = _CountingChatService();
    final notifier = _Seeded(service, [_conv(alreadyRead: false)]);

    expect(await notifier.markAsRead('c1'), isTrue);
    expect(service.markCalls, 1);
  });

  test('an unknown conversation is a no-op, not an exception', () async {
    final service = _CountingChatService();
    final notifier = _Seeded(service, [_conv(alreadyRead: false)]);

    expect(await notifier.markAsRead('does-not-exist'), isFalse);
    expect(service.markCalls, 0);
  });

  test('a failed call leaves the unread count alone', () async {
    final service = _CountingChatService()..fail = true;
    final notifier = _Seeded(service, [_conv(alreadyRead: false, unread: 3)]);

    expect(await notifier.markAsRead('c1'), isFalse);
    expect(notifier.state.value!.single.unreadCount, 3);
  });
}
