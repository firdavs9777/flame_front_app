import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/screens/chat/state/message_thread_provider.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/services/flame_socket_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

Message m(String id, String text, {bool deleted = false}) =>
    Message.fromJson({
      'id': id,
      'sender_id': 'u2',
      'text': text,
      'created_at': '2026-08-18T10:00:00.000Z',
      'is_deleted': deleted,
    });

class _FakeSocket extends FlameSocketService {
  _FakeSocket(String token) : super(token: token);
  @override
  void connect() {}
  @override
  void dispose() {}
  @override
  bool get isConnected => true;
}

class _EmptyService extends ChatService {
  @override
  Future<ServiceResult<MessagesResult>> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
    String? before,
  }) async =>
      ServiceResult.success(MessagesResult(messages: [], hasMore: false));
}

void main() {
  late RealtimeConnection conn;
  late _FakeSocket socket;

  setUp(() {
    socket = _FakeSocket('t');
    conn = RealtimeConnection(createSocket: (_) => socket);
    conn.start('t');
  });

  tearDown(() => conn.dispose());

  Future<MessageThreadNotifier> opened() async {
    final n = MessageThreadNotifier(
        conversationId: 'c1', service: _EmptyService(), connection: conn);
    await n.load();
    n.listen();
    return n;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a push for this conversation is appended', () async {
    final n = await opened();

    socket.onMessageNew!(m('m1', 'hi'), 'c1');
    await settle();

    expect(n.state.messages.single.id, 'm1');
  });

  test('a push for another conversation is ignored', () async {
    final n = await opened();

    socket.onMessageNew!(m('m1', 'hi'), 'c2');
    await settle();

    expect(n.state.messages, isEmpty,
        reason: 'one connection fans out to every open thread, so each must '
            'filter to its own');
  });

  test('a push with no conversation id is ignored rather than misfiled',
      () async {
    final n = await opened();

    socket.onMessageNew!(m('m1', 'hi'), null);
    await settle();

    expect(n.state.messages, isEmpty);
  });

  test('an edit replaces the message in place', () async {
    final n = await opened();

    socket.onMessageNew!(m('m1', 'before'), 'c1');
    await settle();
    socket.onMessageEdited!(m('m1', 'after'), 'c1');
    await settle();

    expect(n.state.messages.single.content, 'after');
    expect(n.state.messages.length, 1);
  });

  test('a deletion arrives as a tombstone and replaces in place', () async {
    final n = await opened();

    socket.onMessageNew!(m('m1', 'oops'), 'c1');
    await settle();
    socket.onMessageDeleted!(m('m1', 'oops', deleted: true), 'c1');
    await settle();

    expect(n.state.messages.single.isDeleted, isTrue,
        reason: 'the row stays so the thread does not reflow under the reader');
  });

  test('listen twice does not double-append', () async {
    final n = await opened();
    n.listen();

    socket.onMessageNew!(m('m1', 'hi'), 'c1');
    await settle();

    expect(n.state.messages.length, 1);
  });

  test('dispose cancels the subscriptions', () async {
    final n = await opened();
    n.dispose();

    // Must not throw 'Bad state: Cannot use StateNotifier after dispose'.
    socket.onMessageNew!(m('m1', 'late'), 'c1');
    await settle();
  });
}
