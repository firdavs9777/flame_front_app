import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/services/flame_socket_service.dart';

// A socket that never touches the network. `connect()` in the real service
// calls `socket.connect()` straight away, so a test must not construct one.
class FakeFlameSocket extends FlameSocketService {
  FakeFlameSocket(String token) : super(token: token);

  bool connected = false;
  bool disposed = false;

  @override
  void connect() => connected = true;

  @override
  void dispose() {
    disposed = true;
    connected = false;
  }

  @override
  bool get isConnected => connected;
}

Message _msg(String id) => Message.fromJson({
  'id': id,
  'sender_id': 'u1',
  'text': 'hello',
  'type': 'text',
  'created_at': '2026-08-17T00:01:00.000Z',
});

void main() {
  late List<FakeFlameSocket> made;
  RealtimeConnection build() {
    made = [];
    return RealtimeConnection(createSocket: (token) {
      final s = FakeFlameSocket(token);
      made.add(s);
      return s;
    });
  }

  test('start() with an empty token is a no-op, not a crash', () {
    final conn = build();
    conn.start('');
    expect(conn.socket, isNull);
    expect(conn.isConnected, isFalse);
    conn.dispose();
  });

  test('start() connects exactly one socket', () {
    final conn = build();
    conn.start('token-a');
    expect(made, hasLength(1));
    expect(made.single.connected, isTrue);
    expect(conn.isConnected, isTrue);
    conn.dispose();
  });

  test('start() twice with the same token does not open a second socket', () {
    final conn = build();
    conn.start('token-a');
    conn.start('token-a');
    expect(made, hasLength(1),
        reason: 'a duplicate socket doubles the server-side block lookup on '
            'every delivery and the presence fan-out, for nothing');
    conn.dispose();
  });

  test('start() with a refreshed token replaces the socket', () {
    final conn = build();
    conn.start('token-a');
    conn.start('token-b');
    expect(made, hasLength(2));
    expect(made.first.disposed, isTrue,
        reason: 'the socket authenticated with the expired token must go away');
    expect(conn.socket, same(made.last));
    conn.dispose();
  });

  test('stop() tears the socket down so the next user does not inherit it', () {
    final conn = build();
    conn.start('token-a');
    conn.stop();
    expect(made.single.disposed, isTrue);
    expect(conn.socket, isNull);
    expect(conn.isConnected, isFalse);
    conn.dispose();
  });

  test('stop() is idempotent', () {
    final conn = build();
    conn.start('token-a');
    conn.stop();
    conn.stop();
    expect(conn.socket, isNull);
    conn.dispose();
  });

  test('every listener receives message:new — one does not steal from another',
      () async {
    final conn = build();
    conn.start('token-a');

    final a = <String>[];
    final b = <String>[];
    conn.messageNew.listen((e) => a.add(e.message.id));
    conn.messageNew.listen((e) => b.add(e.message.id));

    made.single.onMessageNew!(_msg('m1'), 'c1');
    await Future<void>.delayed(Duration.zero);

    expect(a, ['m1']);
    expect(b, ['m1'],
        reason: 'the conversation list and an open ChatScreen must both hear it');
    conn.dispose();
  });

  test('subscriptions survive a reconnect', () async {
    final conn = build();
    conn.start('token-a');

    final seen = <String>[];
    conn.messageNew.listen((e) => seen.add(e.message.id));

    conn.start('token-b'); // token refresh mid-session
    made.last.onMessageNew!(_msg('m2'), 'c1');
    await Future<void>.delayed(Duration.zero);

    expect(seen, ['m2'],
        reason: 'a listener registered before the refresh must keep working');
    conn.dispose();
  });

  test('read and presence events are re-emitted', () async {
    final conn = build();
    conn.start('token-a');

    RealtimeReadEvent? read;
    RealtimePresenceEvent? presence;
    conn.read.listen((e) => read = e);
    conn.presence.listen((e) => presence = e);

    made.single.onRead!('u2', 'c1');
    made.single.onPresence!('u2', true);
    await Future<void>.delayed(Duration.zero);

    expect(read!.byUserId, 'u2');
    expect(read!.conversationId, 'c1');
    expect(presence!.userId, 'u2');
    expect(presence!.online, isTrue);
    conn.dispose();
  });

  test('the provider hands out one connection per container', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final a = container.read(realtimeConnectionProvider);
    final b = container.read(realtimeConnectionProvider);
    expect(identical(a, b), isTrue);
  });
}
