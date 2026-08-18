import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/chat_provider.dart';
import 'package:flame/services/chat_service.dart';

class _Seeded extends ConversationsNotifier {
  _Seeded(List<Conversation> initial) : super(ChatService()) {
    state = AsyncValue.data(initial);
  }
}

Conversation _conv(String id, {int unread = 0}) => Conversation.fromJson({
      'id': id,
      'other_user': {'id': 'u2', 'name': 'B', 'photos': []},
      'unread_count': unread,
      'last_message': {
        'id': 'old',
        'sender_id': 'u2',
        'text': 'old',
        'created_at': '2026-08-18T09:00:00.000Z',
      },
      'updated_at': '2026-08-18T09:00:00.000Z',
    });

Message _incoming(String id, String text) => Message.fromJson({
      'id': id,
      'sender_id': 'u2',
      'text': text,
      'created_at': '2026-08-18T10:00:00.000Z',
    });

void main() {
  test('a push replaces lastMessage and bumps unread', () {
    final n = _Seeded([_conv('c1', unread: 2)]);

    n.addMessageToConversation('c1', _incoming('m9', 'newest'));

    final c = n.state.value!.single;
    expect(c.lastMessage?.id, 'm9');
    expect(c.lastMessagePreview, 'newest');
    expect(c.unreadCount, 3);
    expect(c.lastMessageAt, DateTime.parse('2026-08-18T10:00:00.000Z'));
  });

  test('the same push twice does not double-count unread', () {
    final n = _Seeded([_conv('c1')]);

    n.addMessageToConversation('c1', _incoming('m9', 'newest'));
    n.addMessageToConversation('c1', _incoming('m9', 'newest'));

    expect(n.state.value!.single.unreadCount, 1);
  });

  test('a push for an unknown conversation touches nothing', () {
    final n = _Seeded([_conv('c1')]);

    n.addMessageToConversation('other', _incoming('m9', 'x'));

    expect(n.state.value!.single.lastMessage?.id, 'old');
    expect(n.state.value!.single.unreadCount, 0);
  });

  test('only the addressed conversation is affected', () {
    final n = _Seeded([_conv('c1'), _conv('c2', unread: 5)]);

    n.addMessageToConversation('c1', _incoming('m9', 'x'));

    final list = n.state.value!;
    expect(list.firstWhere((c) => c.id == 'c1').unreadCount, 1);
    expect(list.firstWhere((c) => c.id == 'c2').unreadCount, 5);
    expect(list.firstWhere((c) => c.id == 'c2').lastMessage?.id, 'old');
  });

  test('applyMessageUpdate rewrites the preview only when it is the edited one',
      () {
    final n = _Seeded([_conv('c1')]);

    n.applyMessageUpdate('c1', _incoming('unrelated', 'nope'));
    expect(n.state.value!.single.lastMessage?.id, 'old',
        reason: 'an edit to a message this surface is not showing is a no-op');

    n.applyMessageUpdate(
      'c1',
      Message.fromJson({
        'id': 'old',
        'sender_id': 'u2',
        'text': 'edited',
        'created_at': '2026-08-18T09:00:00.000Z',
        'is_edited': true,
      }),
    );
    expect(n.state.value!.single.lastMessagePreview, 'edited');
  });

  test('clearUnread zeroes the count without touching the preview', () {
    final n = _Seeded([_conv('c1', unread: 4)]);

    n.clearUnread('c1');

    final c = n.state.value!.single;
    expect(c.unreadCount, 0);
    expect(c.lastMessage?.id, 'old');
  });
}
