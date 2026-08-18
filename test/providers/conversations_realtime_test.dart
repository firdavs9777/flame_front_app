import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/chat_provider.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/services/flame_socket_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

// Seeds state directly so no network is touched.
class _Seeded extends ConversationsNotifier {
  _Seeded(List<Conversation> initial) : super(ChatService()) {
    state = AsyncValue.data(initial);
  }
}

// Same, but records the moment the list handles a push so the ORDER of the
// broadcast listeners can be asserted.
class _Recording extends ConversationsNotifier {
  _Recording(List<Conversation> initial, this.log) : super(ChatService()) {
    state = AsyncValue.data(initial);
  }

  final List<String> log;

  @override
  void addMessageToConversation(String conversationId, Message message) {
    log.add('list');
    super.addMessageToConversation(conversationId, message);
  }
}

// Holds markMessagesAsRead open so a push can land mid-flight, which is the
// only way to reproduce the snapshot-across-await race.
class _GatedChatService extends ChatService {
  final Completer<void> gate = Completer<void>();

  @override
  Future<ServiceResult<void>> markMessagesAsRead(String conversationId) async {
    await gate.future;
    return ServiceResult.success(null);
  }
}

class _SeededWith extends ConversationsNotifier {
  _SeededWith(ChatService service, List<Conversation> initial)
      : super(service) {
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

  test('a read receipt marks the previewed message we sent as read', () {
    final n = _Seeded([_conv('c1', 'u1', 0)]);
    n.addMessageToConversation('c1', _msg('mine', 'me'));

    n.applyReadReceipt('c1', 'u1');

    expect(n.state.valueOrNull!.single.lastMessage!.status, MessageStatus.read);
  });

  test('a receipt does not touch a preview the reader sent themselves', () {
    final n = _Seeded([_conv('c1', 'u1', 0)]);
    n.addMessageToConversation('c1', _msg('theirs', 'u1'));

    n.applyReadReceipt('c1', 'u1');

    // u1 having sent the newest message says nothing about u1 reading ours, and
    // marking their own message 'read' would put a receipt tick on the wrong
    // side of the thread.
    expect(n.state.valueOrNull!.single.lastMessage!.status,
        isNot(MessageStatus.read));
  });

  test('an edit replaces the cached message so the preview is not stale', () {
    final n = _Seeded([_conv('c1', 'u1', 0)]);
    n.addMessageToConversation('c1', _msg('m1', 'u1', text: 'origonal'));

    n.applyMessageUpdate('c1', _msg('m1', 'u1', text: 'original'));

    expect(n.state.valueOrNull!.single.lastMessage?.content, 'original');
  });

  test('an update for a message we never cached is ignored', () {
    final n = _Seeded([_conv('c1', 'u1', 0)]);

    final before = n.state.valueOrNull!.single.lastMessage;

    n.applyMessageUpdate('c1', _msg('ghost', 'u1'));

    expect(n.state.valueOrNull!.single.lastMessage, before,
        reason: 'an update for a message this surface is not showing is a no-op');
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

  // main_shell calls listenToRealtime on EVERY auth-state change. Cancelling
  // and re-registering there moved the list's subscriptions to the end of the
  // broadcast listener order — behind an open ChatScreen's — so the screen's
  // `clearUnread` ran BEFORE the `addMessageToConversation` it exists to
  // cancel out, and the badge lit up for the thread being read.
  test('re-subscribing the same connection keeps the list ahead of a chat '
      'screen that subscribed later', () async {
    final sockets = <_FakeSocket>[];
    final conn = RealtimeConnection(createSocket: (t) {
      final s = _FakeSocket(t);
      sockets.add(s);
      return s;
    });
    addTearDown(conn.dispose);
    conn.start('token-a');

    final log = <String>[];
    final n = _Recording([_conv('c1', 'u1', 0)], log);
    n.listenToRealtime(conn);

    // An open ChatScreen subscribes after the list already has.
    final screenSub = conn.messageNew.listen((_) => log.add('screen'));
    addTearDown(screenSub.cancel);

    // ...and then the shell re-syncs, as it does on any auth-state change.
    n.listenToRealtime(conn);

    sockets.single.onMessageNew!(_msg('m1', 'u1'), 'c1');
    await Future<void>.delayed(Duration.zero);

    expect(log, ['list', 'screen'],
        reason: 're-registering must not move the list behind the screen');
  });

  // The branch introduced the first concurrent writer to this notifier:
  // _onSocketMessageNew calls markAsRead on every push while listenToRealtime
  // is appending to the same state. markAsRead snapshotted the list before its
  // PATCH and wrote that snapshot back after, so anything that arrived in
  // between was silently clobbered.
  test('a push landing during markAsRead is not clobbered by the stale '
      'snapshot', () async {
    final service = _GatedChatService();
    final n = _SeededWith(service, [
      Conversation.fromJson({
        'id': 'c1',
        'other_user': {'id': 'u1', 'name': 'User u1'},
        'unread_count': 1,
        'last_message_at': '2026-08-17T00:00:00.000Z',
        'messages': [
          {
            'id': 'm1',
            'sender_id': 'u1',
            'text': 'first',
            'type': 'text',
            'created_at': '2026-08-17T00:01:00.000Z',
          },
        ],
      }),
    ]);

    final inFlight = n.markAsRead('c1');
    // A second message arrives while the PATCH is still open.
    n.addMessageToConversation('c1', _msg('m2', 'u1', text: 'arrived mid-PATCH'));
    service.gate.complete();
    expect(await inFlight, isTrue);

    expect(n.state.valueOrNull!.single.lastMessage?.id, 'm2',
        reason: 'the message that arrived during the PUT must survive it');
    expect(n.state.valueOrNull!.single.unreadCount, 0);
  });
}
