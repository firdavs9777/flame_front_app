import 'package:flutter_test/flutter_test.dart';
import 'package:flame/providers/auth_provider.dart';
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

// The socket must follow the session: up when authenticated, down on every
// other status. `logout()` and `_handleAuthLost` both land on
// `unauthenticated`, so one rule covers both.
void main() {
  late List<_FakeSocket> made;
  RealtimeConnection build() {
    made = [];
    return RealtimeConnection(createSocket: (t) {
      final s = _FakeSocket(t);
      made.add(s);
      return s;
    });
  }

  test('authenticated starts the connection', () {
    final conn = build();
    addTearDown(conn.dispose);

    applySessionStatus(conn, AuthStatus.authenticated, () => 'token-a');

    expect(conn.isConnected, isTrue);
  });

  test('every non-authenticated status stops it', () {
    for (final status in [
      AuthStatus.unauthenticated,
      AuthStatus.initial,
      AuthStatus.profileIncomplete,
    ]) {
      final conn = build();
      applySessionStatus(conn, AuthStatus.authenticated, () => 'token-a');
      expect(conn.isConnected, isTrue);

      applySessionStatus(conn, status, () => 'token-a');

      expect(conn.socket, isNull,
          reason: '$status must not keep a live socket — the next user would '
              'inherit one authenticated as the previous one');
      expect(made.first.disposed, isTrue);
      conn.dispose();
    }
  });

  test('authenticated with no token does not crash or connect', () {
    final conn = build();
    addTearDown(conn.dispose);

    applySessionStatus(conn, AuthStatus.authenticated, () => null);

    expect(conn.socket, isNull);
    expect(made, isEmpty);
  });

  test('a refreshed token reconnects rather than reusing a dead socket', () {
    final conn = build();
    addTearDown(conn.dispose);

    applySessionStatus(conn, AuthStatus.authenticated, () => 'token-1');
    applySessionStatus(conn, AuthStatus.authenticated, () => 'token-2');

    expect(made, hasLength(2));
    expect(made.first.disposed, isTrue);
  });

  test('repeated authenticated ticks with an unchanged token are cheap', () {
    final conn = build();
    addTearDown(conn.dispose);

    applySessionStatus(conn, AuthStatus.authenticated, () => 'token-1');
    applySessionStatus(conn, AuthStatus.authenticated, () => 'token-1');
    applySessionStatus(conn, AuthStatus.authenticated, () => 'token-1');

    expect(made, hasLength(1),
        reason: 'ref.listen fires on every auth-state change, including ones '
            'that do not affect the token');
  });

  test('stop then start opens a fresh socket', () {
    final conn = build();
    addTearDown(conn.dispose);

    applySessionStatus(conn, AuthStatus.authenticated, () => 'token-1');
    applySessionStatus(conn, AuthStatus.unauthenticated, () => 'token-1');
    applySessionStatus(conn, AuthStatus.authenticated, () => 'token-1');

    expect(conn.isConnected, isTrue);
    expect(made, hasLength(2));
  });
}
