import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/services/flame_socket_service.dart';

class _FakeSocket extends FlameSocketService {
  _FakeSocket(String token) : super(token: token);
  bool disposed = false;
  @override
  void connect() {}
  @override
  void dispose() => disposed = true;
  @override
  bool get isConnected => !disposed;
}

Message _msg(String id) => Message.fromJson({
  'id': id,
  'sender_id': 'u1',
  'text': 'hello',
  'type': 'text',
  'created_at': '2026-08-17T00:01:00.000Z',
});

// The regression this guards: with single-assignment callbacks, an open
// ChatScreen would steal `onMessageNew` from the conversation list, so the
// unread badge would freeze for every OTHER conversation exactly while a chat
// was open — the bug B1 exists to fix.
void main() {
  test('a screen-level listener does not starve the list-level one', () async {
    late _FakeSocket socket;
    final conn = RealtimeConnection(createSocket: (t) {
      socket = _FakeSocket(t);
      return socket;
    });
    addTearDown(conn.dispose);
    conn.start('token-a');

    final list = <String>[];
    conn.messageNew.listen((e) => list.add(e.message.id));

    // A screen opens and subscribes.
    final screen = <String>[];
    final sub = conn.messageNew.listen((e) => screen.add(e.message.id));

    socket.onMessageNew!(_msg('m1'), 'c1');
    await Future<void>.delayed(Duration.zero);
    expect(list, ['m1']);
    expect(screen, ['m1']);

    // The screen closes.
    await sub.cancel();

    socket.onMessageNew!(_msg('m2'), 'c1');
    await Future<void>.delayed(Duration.zero);
    expect(list, ['m1', 'm2'], reason: 'the list keeps receiving after a screen closes');
    expect(screen, ['m1']);
  });

  test('cancelling a subscription does not tear down the shared socket',
      () async {
    late _FakeSocket socket;
    final conn = RealtimeConnection(createSocket: (t) {
      socket = _FakeSocket(t);
      return socket;
    });
    addTearDown(conn.dispose);
    conn.start('token-a');

    final sub = conn.messageNew.listen((_) {});
    await sub.cancel();

    expect(socket.disposed, isFalse,
        reason: 'ChatScreen.dispose must not kill the app-level connection');
    expect(conn.isConnected, isTrue);
  });
}
