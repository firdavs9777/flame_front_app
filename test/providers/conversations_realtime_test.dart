import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/chat_provider.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/services/flame_socket_service.dart';

// Seeds state directly so no network is touched.
class _Seeded extends ConversationsNotifier {
  _Seeded(List<Conversation> initial) : super(ChatService()) {
    state = AsyncValue.data(initial);
  }
}

class _FakeSocket extends FlameSocketService {
  _FakeSocket(String token) : super(token: token);
  @override
  void connect() {}
  @override
  void dispose() {}
  @override
  bool get isConnected => true;
}

// Conversation.fromJson reads: id, match_id, other_user, messages,
// last_message, updated_at | last_message_at, unread_count.
Conversation _conv(String id, String otherId, int unread) =>
    Conversation.fromJson({
      'id': id,
      'other_user': {'id': otherId, 'name': 'User $otherId'},
      'unread_count': unread,
      'last_message_at': '2026-08-17T00:00:00.000Z',
    });

// Message.fromJson reads: id, sender_id, receiver_id, text | content,
// created_at | timestamp, message_type | type. `content` is the field name —
// there is no `Message.text`.
Message _msg(String id, String senderId, {String text = 'hello'}) =>
    Message.fromJson({
      'id': id,
      'sender_id': senderId,
      'text': text,
      'type': 'text',
      'created_at': '2026-08-17T00:01:00.000Z',
    });

void main() {
  test('an incoming message bumps only that conversation\'s unread count', () {
    final n = _Seeded([_conv('c1', 'u1', 0), _conv('c2', 'u2', 3)]);

    n.addMessageToConversation('c1', _msg('m1', 'u1'));

    final list = n.state.valueOrNull!;
    expect(list.firstWhere((c) => c.id == 'c1').unreadCount, 1);
    expect(list.firstWhere((c) => c.id == 'c2').unreadCount, 3,
        reason: 'other conversations must be untouched');
  });

  test('an incoming message updates the preview', () {
    final n = _Seeded([_conv('c1', 'u1', 0)]);

    n.addMessageToConversation('c1', _msg('m1', 'u1', text: 'hi there'));

    expect(n.state.valueOrNull!.single.lastMessage?.content, 'hi there');
  });

  test('a message for an unknown conversation is ignored, not crashed on', () {
    final n = _Seeded([_conv('c1', 'u1', 0)]);

    n.addMessageToConversation('nope', _msg('m1', 'u9'));

    expect(n.state.valueOrNull!.single.unreadCount, 0);
  });

  test('clearUnread zeroes one conversation only, without a network call', () {
    final n = _Seeded([_conv('c1', 'u1', 5), _conv('c2', 'u2', 2)]);

    n.clearUnread('c1');

    final list = n.state.valueOrNull!;
    expect(list.firstWhere((c) => c.id == 'c1').unreadCount, 0);
    expect(list.firstWhere((c) => c.id == 'c2').unreadCount, 2);
  });

  test('a read receipt from the other user does NOT clear our unread count',
      () {
    final n = _Seeded([_conv('c1', 'u1', 4)]);

    // u1 is the other participant. Them reading says nothing about what we
    // have read.
    n.applyReadReceipt('c1', 'u1');

    expect(n.state.valueOrNull!.single.unreadCount, 4,
        reason: 'their read receipt must not wipe our badge');
  });

  test('a read receipt marks the messages we sent as read', () {
    final n = _Seeded([_conv('c1', 'u1', 0)]);
    n.addMessageToConversation('c1', _msg('mine', 'me'));
    n.addMessageToConversation('c1', _msg('theirs', 'u1'));

    n.applyReadReceipt('c1', 'u1');

    final msgs = n.state.valueOrNull!.single.messages;
    expect(msgs.firstWhere((m) => m.id == 'mine').status, MessageStatus.read);
    expect(msgs.firstWhere((m) => m.id == 'theirs').status,
        isNot(MessageStatus.read),
        reason: 'a message the reader sent themselves is not their own receipt');
  });

  test('an edit replaces the cached message so the preview is not stale', () {
    final n = _Seeded([_conv('c1', 'u1', 0)]);
    n.addMessageToConversation('c1', _msg('m1', 'u1', text: 'origonal'));

    n.applyMessageUpdate('c1', _msg('m1', 'u1', text: 'original'));

    expect(n.state.valueOrNull!.single.lastMessage?.content, 'original');
  });

  test('an update for a message we never cached is ignored', () {
    final n = _Seeded([_conv('c1', 'u1', 0)]);

    n.applyMessageUpdate('c1', _msg('ghost', 'u1'));

    expect(n.state.valueOrNull!.single.messages, isEmpty);
  });

  test('presence flips the online dot for the matching conversation only', () {
    final n = _Seeded([_conv('c1', 'u1', 0), _conv('c2', 'u2', 0)]);

    n.applyPresence('u1', true);

    final list = n.state.valueOrNull!;
    expect(list.firstWhere((c) => c.id == 'c1').otherUser.isOnline, isTrue);
    expect(list.firstWhere((c) => c.id == 'c2').otherUser.isOnline, isFalse);
  });

  test('the badge total reflects a live socket push', () async {
    final sockets = <_FakeSocket>[];
    final conn = RealtimeConnection(createSocket: (t) {
      final s = _FakeSocket(t);
      sockets.add(s);
      return s;
    });
    addTearDown(conn.dispose);

    final container = ProviderContainer(overrides: [
      conversationsProvider.overrideWith(
        (ref) => _Seeded([_conv('c1', 'u1', 0), _conv('c2', 'u2', 2)]),
      ),
    ]);
    addTearDown(container.dispose);

    expect(container.read(chatUnreadCountProvider), 2);

    conn.start('token-a');
    container.read(conversationsProvider.notifier).listenToRealtime(conn);

    sockets.single.onMessageNew!(_msg('m1', 'u1'), 'c1');
    await Future<void>.delayed(Duration.zero);

    expect(container.read(chatUnreadCountProvider), 3,
        reason: 'the nav badge must move without a refetch');
  });

  test('listenToRealtime twice does not double-count', () async {
    final sockets = <_FakeSocket>[];
    final conn = RealtimeConnection(createSocket: (t) {
      final s = _FakeSocket(t);
      sockets.add(s);
      return s;
    });
    addTearDown(conn.dispose);

    final n = _Seeded([_conv('c1', 'u1', 0)]);
    conn.start('token-a');
    n.listenToRealtime(conn);
    n.listenToRealtime(conn);

    sockets.single.onMessageNew!(_msg('m1', 'u1'), 'c1');
    await Future<void>.delayed(Duration.zero);

    expect(n.state.valueOrNull!.single.unreadCount, 1);
  });
}
