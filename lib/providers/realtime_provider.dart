import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/services/flame_socket_service.dart';

/// A `message:new` / `message:edited` / `message:deleted` push.
///
/// [conversationId] travels beside the message because `Message` (shared with
/// the REST paths) carries no conversation id of its own.
class RealtimeMessageEvent {
  final Message message;
  final String? conversationId;
  const RealtimeMessageEvent(this.message, this.conversationId);
}

class RealtimeTypingEvent {
  final String fromUserId;
  final String conversationId;
  const RealtimeTypingEvent(this.fromUserId, this.conversationId);
}

/// The *other* participant read this conversation. This is a receipt for
/// messages **we** sent — it says nothing about our own unread count.
class RealtimeReadEvent {
  final String byUserId;
  final String conversationId;
  const RealtimeReadEvent(this.byUserId, this.conversationId);
}

class RealtimePresenceEvent {
  final String userId;
  final bool online;
  const RealtimePresenceEvent(this.userId, this.online);
}

/// Owns the app's single realtime connection and fans its events out.
///
/// Before this existed, the only socket was created inside `ChatScreen`, so
/// nothing was listening once you left a conversation — the Messages list and
/// the unread badge went stale until a manual refetch. The backend was already
/// pushing; nobody was receiving.
///
/// Two design points, both load-bearing:
///
/// 1. **One connection, not one per screen.** The server re-checks blocks on
///    every delivery (`flameSocket.emitToReceiver`), so a second socket doubles
///    that lookup and the presence fan-out for no benefit.
/// 2. **Streams, not callbacks.** `FlameSocketService`'s callbacks are single
///    assignment. This class claims them once and re-emits through broadcast
///    streams, so the conversation list and an open chat can both listen
///    instead of clobbering each other.
class RealtimeConnection {
  // The factory only BUILDS the socket; `start` connects it. Having both do it
  // meant the real path called connect() twice — harmless, since the second
  // call early-returns, but confusing to read.
  RealtimeConnection({FlameSocketService Function(String token)? createSocket})
      : _createSocket =
            createSocket ?? ((token) => FlameSocketService(token: token));

  final FlameSocketService Function(String token) _createSocket;

  FlameSocketService? _socket;
  String? _token;

  // Long-lived: they outlast individual sockets so a listener registered
  // before a token refresh keeps working after it.
  final _messageNew = StreamController<RealtimeMessageEvent>.broadcast();
  final _messageEdited = StreamController<RealtimeMessageEvent>.broadcast();
  final _messageDeleted = StreamController<RealtimeMessageEvent>.broadcast();
  final _typing = StreamController<RealtimeTypingEvent>.broadcast();
  final _stopTyping = StreamController<RealtimeTypingEvent>.broadcast();
  final _read = StreamController<RealtimeReadEvent>.broadcast();
  final _presence = StreamController<RealtimePresenceEvent>.broadcast();
  final _presenceBulk = StreamController<List<String>>.broadcast();

  Stream<RealtimeMessageEvent> get messageNew => _messageNew.stream;
  Stream<RealtimeMessageEvent> get messageEdited => _messageEdited.stream;
  Stream<RealtimeMessageEvent> get messageDeleted => _messageDeleted.stream;
  Stream<RealtimeTypingEvent> get typing => _typing.stream;
  Stream<RealtimeTypingEvent> get stopTyping => _stopTyping.stream;
  Stream<RealtimeReadEvent> get read => _read.stream;
  Stream<RealtimePresenceEvent> get presence => _presence.stream;
  Stream<List<String>> get presenceBulk => _presenceBulk.stream;

  /// The live socket, exposed only so callers can emit (`emitTyping`,
  /// `emitMarkRead`). Do not assign its callbacks — this class owns them.
  FlameSocketService? get socket => _socket;

  bool get isConnected => _socket?.isConnected ?? false;

  /// Opens the connection, or replaces it when the token has changed.
  ///
  /// Replacing on a new token matters: `ApiClient` refreshes proactively, and a
  /// socket authenticated with the old token stays dead after it expires.
  void start(String token) {
    if (token.isEmpty) return;
    if (_socket != null && _token == token) return;

    stop();
    _token = token;

    final socket = _createSocket(token);
    socket.onMessageNew = (m, c) => _add(_messageNew, RealtimeMessageEvent(m, c));
    socket.onMessageEdited = (m, c) => _add(_messageEdited, RealtimeMessageEvent(m, c));
    socket.onMessageDeleted = (m, c) => _add(_messageDeleted, RealtimeMessageEvent(m, c));
    socket.onTyping = (f, c) => _add(_typing, RealtimeTypingEvent(f, c));
    socket.onStopTyping = (f, c) => _add(_stopTyping, RealtimeTypingEvent(f, c));
    socket.onRead = (b, c) => _add(_read, RealtimeReadEvent(b, c));
    socket.onPresence = (u, o) => _add(_presence, RealtimePresenceEvent(u, o));
    socket.onPresenceBulk = (ids) => _add(_presenceBulk, ids);
    socket.connect();

    _socket = socket;
  }

  /// Tears the connection down. Must be called on logout, or the next user
  /// inherits a socket authenticated as the previous one. The streams stay
  /// open so subscribers survive a reconnect.
  void stop() {
    _socket?.dispose();
    _socket = null;
    _token = null;
  }

  /// Permanent teardown — closes the streams too. Only the provider calls this.
  void dispose() {
    stop();
    _messageNew.close();
    _messageEdited.close();
    _messageDeleted.close();
    _typing.close();
    _stopTyping.close();
    _read.close();
    _presence.close();
    _presenceBulk.close();
  }

  // A push arriving after teardown is normal, not an error: Socket.IO can
  // deliver one frame between logout and the socket actually closing.
  void _add<T>(StreamController<T> c, T event) {
    if (!c.isClosed) c.add(event);
  }
}

final realtimeConnectionProvider = Provider<RealtimeConnection>((ref) {
  final conn = RealtimeConnection();
  ref.onDispose(conn.dispose);
  return conn;
});

/// Applies an auth-status change to the realtime connection.
///
/// A free function taking the status and a token supplier, rather than a hook
/// on `AuthNotifier`: that notifier cannot be constructed in a unit test (its
/// constructor reads secure storage over a platform channel), so a callback
/// there would be untestable. This is pure with respect to both auth and the
/// network.
///
/// Only `authenticated` keeps a socket. `profileIncomplete` and `registering`
/// are mid-onboarding — there is nothing to receive yet — and leaving one open
/// through `unauthenticated` would hand the next user a socket authenticated
/// as the previous one.
void applySessionStatus(
  RealtimeConnection conn,
  AuthStatus status,
  String? Function() tokenOf,
) {
  if (status != AuthStatus.authenticated) {
    conn.stop();
    return;
  }
  final token = tokenOf();
  if (token == null || token.isEmpty) return;
  // `start` is a no-op when the token is unchanged, so calling this on every
  // auth transition is cheap; when ApiClient has refreshed proactively it
  // replaces the socket that is now holding a dead token.
  conn.start(token);
}
