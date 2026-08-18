import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/screens/chat/state/thread_presence_provider.dart';
import 'package:flame/services/flame_socket_service.dart';

class _FakeSocket extends FlameSocketService {
  _FakeSocket(String token) : super(token: token);

  int typingEmits = 0;
  int stopTypingEmits = 0;

  @override
  void connect() {}
  @override
  void dispose() {}
  @override
  bool get isConnected => true;

  @override
  void emitTyping(String to, String conversationId) => typingEmits++;
  @override
  void emitStopTyping(String to, String conversationId) => stopTypingEmits++;
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

  ThreadPresenceNotifier make({bool seedOnline = false}) =>
      ThreadPresenceNotifier(
        conversationId: 'c1',
        otherUserId: 'u2',
        seedOnline: seedOnline,
        connection: conn,
      )..listen();

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('seeds online from the REST snapshot', () {
    expect(make(seedOnline: true).state.isOtherOnline, isTrue);
    expect(make(seedOnline: false).state.isOtherOnline, isFalse);
  });

  test('typing then stopTyping shows and hides the indicator', () async {
    final n = make();

    socket.onTyping!('u2', 'c1');
    await settle();
    expect(n.state.isOtherTyping, isTrue);

    socket.onStopTyping!('u2', 'c1');
    await settle();
    expect(n.state.isOtherTyping, isFalse);
  });

  test('a typing event for another thread is ignored', () async {
    final n = make();

    socket.onTyping!('u2', 'c2');
    await settle();

    expect(n.state.isOtherTyping, isFalse);
  });

  test('presence updates the dot, and only for the right user', () async {
    final n = make();

    socket.onPresence!('u2', true);
    await settle();
    expect(n.state.isOtherOnline, isTrue);

    socket.onPresence!('someone-else', false);
    await settle();
    expect(n.state.isOtherOnline, isTrue,
        reason: 'another user going offline says nothing about this partner');
  });

  test('presence:bulk that omits the partner marks them offline', () async {
    final n = make(seedOnline: true);

    socket.onPresenceBulk!(['u3', 'u4']);
    await settle();

    expect(n.state.isOtherOnline, isFalse);
  });

  test('presence:bulk that includes the partner marks them online', () async {
    final n = make();

    socket.onPresenceBulk!(['u2', 'u3']);
    await settle();

    expect(n.state.isOtherOnline, isTrue);
  });

  test('the indicator hides itself if stopTyping is dropped', () {
    fakeAsync((async) {
      final n = make();

      socket.onTyping!('u2', 'c1');
      async.flushMicrotasks();
      expect(n.state.isOtherTyping, isTrue);

      async.elapse(const Duration(seconds: 6));
      expect(n.state.isOtherTyping, isFalse,
          reason: 'a dropped stopTyping must not strand the indicator on');
    });
  });

  test('each typing event restarts the safety timer', () {
    fakeAsync((async) {
      final n = make();

      socket.onTyping!('u2', 'c1');
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 4));
      socket.onTyping!('u2', 'c1');
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 4));

      expect(n.state.isOtherTyping, isTrue,
          reason: 'still typing — 8s elapsed but never 5s without an event');
    });
  });

  test('outgoing typing is emitted once per run, not per keystroke', () {
    fakeAsync((async) {
      final n = make();

      n.onOutgoingText('h');
      n.onOutgoingText('he');
      n.onOutgoingText('hel');
      expect(socket.typingEmits, 1);

      async.elapse(const Duration(seconds: 4));
      expect(socket.stopTypingEmits, 1,
          reason: 'idle ends the run without another keystroke');
    });
  });

  test('clearing the composer ends the run immediately', () {
    fakeAsync((async) {
      final n = make();

      n.onOutgoingText('h');
      n.onOutgoingText('');

      expect(socket.stopTypingEmits, 1);
      async.elapse(const Duration(seconds: 5));
      expect(socket.stopTypingEmits, 1, reason: 'not emitted twice');
    });
  });

  test('dispose ends an open run so the partner is not left seeing dots', () {
    final n = make();
    n.onOutgoingText('h');
    expect(socket.typingEmits, 1);

    n.dispose();

    expect(socket.stopTypingEmits, 1);
  });
}
