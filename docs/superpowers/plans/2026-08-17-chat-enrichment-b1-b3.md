# Chat Enrichment B1–B3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make chat live outside an open conversation, and give the media, pin and mute endpoints the shipped app already calls a backend to talk to.

**Architecture:** One app-level Socket.IO connection owned by a Riverpod provider feeds the conversation list and unread badge; `ChatScreen` subscribes to it instead of opening a second. On the backend, media messages reuse the proven multer → S3 path from photo upload, and conversation controls copy BananaTalk's per-user array shape.

**Tech Stack:** Flutter/Riverpod/socket_io_client. Node/Express, Mongoose on Flame's own `getConn()` connection, multer memory storage, DigitalOcean Spaces via `flame/utils/s3.js`. Tests: `node:test` + `mongodb-memory-server`; `flutter test`.

**Spec:** `docs/superpowers/specs/2026-08-17-chat-enrichment-design.md`

**Scope:** B1 (realtime), B2 (media), B3 (conversation controls). **B4 (stickers) is cut** — see the spec. **B5 (search/forward/disappearing) gets its own plan** — it is independent new product surface.

## Global Constraints

- **Two repos.** Backend: `~/Projects/BananaTalk/backend` (paths relative to it unless marked **APP**). App: `~/Desktop/Flame/flame_front_app` (marked **APP**).
- **Backend: only touch files under `flame/`.** BananaTalk's own code at the repo root serves live users.
- Flame models end with `module.exports = getConn().model('Name', schema);` — never `mongoose.model()`.
- User ids are `String`. `auth` sets `req.user = { id: payload.userId }`.
- Response envelope is `{ success: true, data: {...} }`; errors come from `flame/utils/errors.js`.
- **Every message-creating route must run `visibility.assertCanInteract` AND the ended-match check** (`matchService.isEndedBetween`), exactly as `chatService.sendMessage` does. A media route that skips them reopens a hole Phase A closed.
- **Response shapes are contracts with the already-shipped app.** Media routes, field names and JSON keys are fixed — see each task.
- Backend tests: `node --test flame/__tests__/<file>` — **run in the FOREGROUND, one file at a time.** Never background a test run; never run the whole suite (it is slow and has hung agents before).
- **Standing test corrections** (these bit six tasks in Phase A):
  1. Fixture user names must be ≥2 characters (`User.name` has `minlength: 2`).
  2. Set `FLAME_SPACES_BUCKET`, `SPACES_ENDPOINT`, `DO_SPACES_KEY`, `DO_SPACES_SECRET` before requires — `flame/utils/s3.js` throws at module load without them.
  3. Clear every service you require from the require-cache array, including `matchService` and `Match` for anything touching chat.
- **Before deploying:** run `node flame/scripts/drop-legacy-indexes.js` against the target database and read the report. `flame_db` has held collections from an earlier schema whose unique indexes broke Phase A in production while every test passed.

---

### Task 1: App-level realtime connection with fan-out streams

**Files:**
- Create: `APP lib/providers/realtime_provider.dart`
- Test: `APP test/providers/realtime_provider_test.dart`

**Interfaces:**
- Consumes: `FlameSocketService` (`APP lib/services/flame_socket_service.dart`). Its real shape, verified — do not guess:
  - constructor `FlameSocketService({required String token})`
  - `void connect()`, `void dispose()`, `bool get isConnected`
  - assignable callback **fields** (single-assignment, not listener lists):
    `onMessageNew(Message, String?)`, `onMessageEdited(Message, String?)`,
    `onMessageDeleted(Message, String?)`, `onTyping(String from, String convId)`,
    `onStopTyping(String from, String convId)`, `onRead(String by, String convId)`,
    `onPresence(String userId, bool online)`, `onPresenceBulk(List<String>)`
  - emitters `emitTyping(to, convId)`, `emitStopTyping(to, convId)`, `emitMarkRead(to, convId)`
- Produces:
  - event types `RealtimeMessageEvent`, `RealtimeTypingEvent`, `RealtimeReadEvent`, `RealtimePresenceEvent`
  - `RealtimeConnection` with `start(String token)`, `stop()`, `dispose()`, `bool get isConnected`, `FlameSocketService? get socket`, and the broadcast streams `messageNew`, `messageEdited`, `messageDeleted`, `typing`, `stopTyping`, `read`, `presence`, `presenceBulk`
  - `realtimeConnectionProvider` — `Provider<RealtimeConnection>`

**Why streams and not callbacks.** `FlameSocketService`'s callbacks are single
assignment: `socket.onMessageNew = x` *replaces* whatever was there. If both the
conversations list and an open `ChatScreen` assigned them directly, the screen
would silently steal every event from the list, and the unread badge would stop
moving for every *other* conversation exactly while a chat is open — which is the
bug B1 exists to fix. `RealtimeConnection` claims those fields once and re-emits
through broadcast streams, so both can listen.

**Why an injectable factory.** `FlameSocketService.connect()` calls
`socket.connect()` immediately — a real network attempt. Constructing one inside a
`flutter test` leaves a pending connection and can fail the test with a pending
timer. `RealtimeConnection` therefore takes a `createSocket` factory, defaulted to
the real thing, and the tests pass a fake.

- [ ] **Step 1: Write the failing test**

Create `APP test/providers/realtime_provider_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Desktop/Flame/flame_front_app && flutter test test/providers/realtime_provider_test.dart`
Expected: FAIL — `Error when reading 'lib/providers/realtime_provider.dart'`

- [ ] **Step 3: Write the connection**

Create `APP lib/providers/realtime_provider.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
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
  RealtimeConnection({FlameSocketService Function(String token)? createSocket})
      : _createSocket = createSocket ??
            ((token) => FlameSocketService(token: token)..connect());

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
    socket
      ..onMessageNew = (m, c) => _add(_messageNew, RealtimeMessageEvent(m, c))
      ..onMessageEdited =
          (m, c) => _add(_messageEdited, RealtimeMessageEvent(m, c))
      ..onMessageDeleted =
          (m, c) => _add(_messageDeleted, RealtimeMessageEvent(m, c))
      ..onTyping = (f, c) => _add(_typing, RealtimeTypingEvent(f, c))
      ..onStopTyping = (f, c) => _add(_stopTyping, RealtimeTypingEvent(f, c))
      ..onRead = (b, c) => _add(_read, RealtimeReadEvent(b, c))
      ..onPresence = (u, o) => _add(_presence, RealtimePresenceEvent(u, o))
      ..onPresenceBulk = (ids) => _add(_presenceBulk, ids);

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/realtime_provider_test.dart`
Expected: PASS — 10 tests

- [ ] **Step 5: Commit**

```bash
cd ~/Desktop/Flame/flame_front_app
git add lib/providers/realtime_provider.dart test/providers/realtime_provider_test.dart
git commit -m "feat(realtime): add the app-level socket connection with fan-out streams"
```

---

### Task 2: Keep the conversation list and unread badge live

**Files:**
- Modify: `APP lib/providers/chat_provider.dart`
- Test: `APP test/providers/conversations_realtime_test.dart`

**Interfaces:**
- Consumes: `RealtimeConnection`, `RealtimeMessageEvent`, `RealtimeReadEvent` (Task 1)
- Produces on `ConversationsNotifier`:
  - `void clearUnread(String conversationId)` — zero the badge locally, no network
  - `void applyReadReceipt(String conversationId, String byUserId)` — mark messages we sent as read
  - `void applyMessageUpdate(String conversationId, Message message)` — replace an edited or deleted message in the cache so the preview stops showing stale text
  - `void applyPresence(String userId, bool online)` — flip the online dot in the list
  - `void listenToRealtime(RealtimeConnection conn)` — idempotent subscribe

**Two things this task must NOT get wrong.**

**(a) `addMessageToConversation` already exists** (`chat_provider.dart:432`) and
already does the right thing: it appends to `messages`, bumps `lastMessageAt`,
increments `unreadCount`, and **de-dupes by message id**. Reuse it. Do not add a
second near-identical method. Note also that `Conversation` has **no
`lastMessage` field** — `lastMessage` is a getter over `messages.last`, so there
is nothing named `lastMessage` to pass to `copyWith`.

**(b) The `read` socket event does NOT mean "clear my unread".** The server
relays it when the *other* participant reads, carrying `by`. Zeroing our own
unread count on it would wipe the badge every time the other person opened the
thread. Our unread clears when *we* open a conversation, which the existing
`markAsRead` already handles. `read` is a receipt for messages **we** sent.

**Delete the dead handlers.** `ConversationsNotifier` still carries orphans from
the removed `WebSocketService`: `_initWebSocket` (empty, called from the
constructor at line 29), `_onNewMessage`, `_onMessageStatus`, `_onUserOnline`,
`_onUserOffline`, `_onMessageEdited`, `_onMessageDeleted`, `_onReactionAdded`,
`_onReactionRemoved` — all taking `Map<String, dynamic>` from the old wire
protocol. Nothing calls any of them. Read them for the state-shape logic they
encode, then delete them and the `_initWebSocket()` call, rather than leaving two
parallel sets of handlers to wire the wrong one from.

- [ ] **Step 1: Write the failing test**

Create `APP test/providers/conversations_realtime_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/conversations_realtime_test.dart`
Expected: FAIL — `clearUnread` / `applyReadReceipt` / `listenToRealtime` are not defined

- [ ] **Step 3: Add the state transitions**

In `APP lib/providers/chat_provider.dart`, inside `ConversationsNotifier`, beside
the existing `addMessageToConversation`:

```dart
  /// Zeroes the unread badge for one conversation, with no network call.
  ///
  /// Separate from [markAsRead], which also PATCHes the server: when a push
  /// lands for the thread the user already has open, the server has been told
  /// already and only the local badge is stale.
  void clearUnread(String conversationId) {
    final conversations = state.valueOrNull;
    if (conversations == null) return;

    state = AsyncValue.data(
      conversations
          .map((c) => c.id == conversationId ? c.copyWith(unreadCount: 0) : c)
          .toList(),
    );
  }

  /// Applies the other participant's read receipt.
  ///
  /// This marks the messages WE sent as read. It must not touch
  /// [Conversation.unreadCount] — that counts messages waiting for us, and the
  /// other person reading their inbox says nothing about ours. Getting this
  /// backwards would blank the badge every time they opened the thread.
  void applyReadReceipt(String conversationId, String byUserId) {
    final conversations = state.valueOrNull;
    if (conversations == null) return;

    state = AsyncValue.data(
      conversations.map((c) {
        if (c.id != conversationId) return c;
        return c.copyWith(
          messages: c.messages
              .map((m) => m.senderId == byUserId
                  ? m
                  : m.copyWith(status: MessageStatus.read))
              .toList(),
        );
      }).toList(),
    );
  }

  /// Replaces an edited or deleted message in the cached list.
  ///
  /// Without this the Messages preview keeps showing the original text of a
  /// message the sender has since edited or deleted — the list reads
  /// `messages.last`, so a stale entry there is visible on the main screen.
  /// A message we have not cached is ignored: the next fetch brings it in whole.
  void applyMessageUpdate(String conversationId, Message message) {
    final conversations = state.valueOrNull;
    if (conversations == null) return;

    state = AsyncValue.data(
      conversations.map((c) {
        if (c.id != conversationId) return c;
        if (!c.messages.any((m) => m.id == message.id)) return c;
        return c.copyWith(
          messages:
              c.messages.map((m) => m.id == message.id ? message : m).toList(),
        );
      }).toList(),
    );
  }

  /// Flips the online dot in the Messages list.
  ///
  /// Presence used to be whatever the last REST fetch said, so the dots were
  /// only ever correct at load time.
  void applyPresence(String userId, bool online) {
    final conversations = state.valueOrNull;
    if (conversations == null) return;

    state = AsyncValue.data(
      conversations.map((c) {
        if (c.otherUser.id != userId) return c;
        if (c.otherUser.isOnline == online) return c;
        return c.copyWith(otherUser: c.otherUser.copyWith(isOnline: online));
      }).toList(),
    );
  }
```

- [ ] **Step 4: Subscribe to the app-level connection**

Still in `ConversationsNotifier`, add the subscription plumbing and a `dispose`
override. `StreamSubscription` needs `dart:async` — add the import.

```dart
  final List<StreamSubscription<void>> _realtimeSubs = [];

  /// Subscribes the conversation list to the app-level socket.
  ///
  /// Idempotent: a second call cancels the first set rather than stacking a
  /// duplicate that would count every message twice.
  void listenToRealtime(RealtimeConnection conn) {
    for (final s in _realtimeSubs) {
      s.cancel();
    }
    _realtimeSubs.clear();

    _realtimeSubs.addAll([
      conn.messageNew.listen((e) {
        final id = e.conversationId;
        if (id != null) addMessageToConversation(id, e.message);
      }),
      conn.messageEdited.listen((e) {
        final id = e.conversationId;
        if (id != null) applyMessageUpdate(id, e.message);
      }),
      conn.messageDeleted.listen((e) {
        final id = e.conversationId;
        if (id != null) applyMessageUpdate(id, e.message);
      }),
      conn.read.listen((e) => applyReadReceipt(e.conversationId, e.byUserId)),
      conn.presence.listen((e) => applyPresence(e.userId, e.online)),
      conn.presenceBulk.listen((ids) {
        final online = ids.toSet();
        for (final c in state.valueOrNull ?? const <Conversation>[]) {
          applyPresence(c.otherUser.id, online.contains(c.otherUser.id));
        }
      }),
    ]);
  }

  @override
  void dispose() {
    for (final s in _realtimeSubs) {
      s.cancel();
    }
    _realtimeSubs.clear();
    super.dispose();
  }
```

Import `realtime_provider.dart` for `RealtimeConnection`.

- [ ] **Step 5: Delete the dead handlers**

Remove `_initWebSocket()` and its call from the constructor (line ~29), plus
`_onNewMessage`, `_onMessageStatus`, `_onUserOnline`, `_onUserOffline`,
`_onMessageEdited`, `_onMessageDeleted`, `_onReactionAdded`,
`_onReactionRemoved`. Keep any private helper they called that the live code
still uses — `_updateMessageInConversation` is one; check each before deleting.
If removing them makes an import unused (`flutter/foundation.dart` for
`debugPrint`), remove the import too.

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/providers/conversations_realtime_test.dart`
Expected: PASS — 11 tests

- [ ] **Step 7: Run the whole app suite**

Run: `flutter test && flutter analyze`
Expected: all pass, zero analyzer errors. Deleting the orphaned handlers may
break a test that referenced them — fix the test rather than restoring dead code.

- [ ] **Step 8: Commit**

```bash
git add lib/providers/chat_provider.dart test/providers/conversations_realtime_test.dart
git commit -m "feat(realtime): keep the conversation list and unread badge live"
```

---

### Task 3: Start and stop the socket with the session

**Files:**
- Modify: `APP lib/providers/realtime_provider.dart` (add `applySessionStatus`)
- Modify: `APP lib/screens/main_shell.dart`
- Test: `APP test/providers/realtime_lifecycle_test.dart`

**Interfaces:**
- Consumes: `RealtimeConnection.start/stop` (Task 1), `ConversationsNotifier.listenToRealtime` (Task 2)
- Produces: `void applySessionStatus(RealtimeConnection conn, AuthStatus status, String? Function() tokenOf)`

**Do not add a callback to `AuthNotifier`.** An earlier draft of this plan had
`AuthNotifier.onSessionEnded`, tested by instantiating the notifier. That test
cannot be written: `AuthNotifier()`'s constructor calls `_init()`, which reads
`flutter_secure_storage` over a platform channel, and `logout()` calls the
network. The repo's own `test/providers/auth_session_retention_test.dart` tests
only `AuthNotifier`'s **static** methods for exactly this reason.

Instead the transition rule is a free function taking the status and a token
supplier. It is pure with respect to both auth and the network, so it is fully
testable, and `auth_provider.dart` is not touched at all. `logout()` and
`_handleAuthLost` both land on `AuthStatus.unauthenticated`, so one rule covers
both without either knowing this feature exists.

- [ ] **Step 1: Write the failing test**

Create `APP test/providers/realtime_lifecycle_test.dart`:

```dart
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
      AuthStatus.registering,
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/realtime_lifecycle_test.dart`
Expected: FAIL — `applySessionStatus` is not defined

- [ ] **Step 3: Add the transition rule**

At the bottom of `APP lib/providers/realtime_provider.dart`, below the provider:

```dart
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
```

Import `package:flame/providers/auth_provider.dart` for `AuthStatus`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/realtime_lifecycle_test.dart`
Expected: PASS — 6 tests

- [ ] **Step 5: Wire it in the shell**

`APP lib/screens/main_shell.dart` already has a post-frame `_initialized` guard
calling `_initializeData()`. Extend that method — do not add a second callback:

```dart
  Future<void> _initializeData() async {
    // Load user profile.
    await ref.read(currentUserProvider.notifier).loadUser();

    if (EnvConfig.current.chatEnabled) {
      await ref.read(conversationsProvider.notifier).loadConversations(refresh: true);
      _syncRealtime(ref.read(authProvider).status);
    }
  }

  /// The socket lives as long as the signed-in session. Starting it here rather
  /// than in ChatScreen is the whole point of B1: the Messages list and the
  /// unread badge must stay live when no conversation is open.
  void _syncRealtime(AuthStatus status) {
    final conn = ref.read(realtimeConnectionProvider);
    applySessionStatus(conn, status, () => ApiClient().accessToken);
    if (conn.socket != null) {
      ref.read(conversationsProvider.notifier).listenToRealtime(conn);
    }
  }
```

and in `build`, before returning the `Scaffold`:

```dart
    // ApiClient refreshes the access token proactively, so a socket may be
    // holding a dead one; and logout must tear it down. Both arrive here as an
    // auth-state change.
    ref.listen(authProvider, (_, next) {
      if (!EnvConfig.current.chatEnabled) return;
      _syncRealtime(next.status);
    });
```

`ref.listen` belongs in `build` for a `ConsumerStatefulWidget` — Riverpod
deduplicates it across rebuilds. Import
`package:flame/providers/realtime_provider.dart` and
`package:flame/services/api_client.dart`; `authProvider` and `AuthStatus` come
from `providers.dart`, which is already imported — verify that export before
adding a second import.

- [ ] **Step 6: Run the whole app suite**

Run: `flutter test && flutter analyze`
Expected: all tests pass, zero analyzer errors.

- [ ] **Step 7: Commit**

```bash
git add lib/providers/realtime_provider.dart lib/screens/main_shell.dart test/providers/realtime_lifecycle_test.dart
git commit -m "feat(realtime): tie the app socket to the session lifecycle"
```

---

### Task 4: ChatScreen subscribes instead of opening its own socket

**Files:**
- Modify: `APP lib/screens/chat/chat_screen.dart`
- Test: `APP test/providers/realtime_fanout_test.dart`

**Interfaces:**
- Consumes: `realtimeConnectionProvider`, the `RealtimeConnection` streams (Task 1), `ConversationsNotifier.clearUnread` (Task 2)
- Produces: no new exports

`ChatScreen._connectFlameSocket()` (`chat_screen.dart:221`) constructs its own
`FlameSocketService` and `dispose()` (line 100) calls `_flameSocket?.dispose()`.
That means two sockets per user whenever a chat is open — doubling every
`areBlocked` lookup in `flameSocket.emitToReceiver` and the presence fan-out.

The screen keeps its `_flameSocket` field: it still needs the socket to **emit**
(`emitTyping`, `emitStopTyping`, `emitMarkRead` at lines 95, 354, 383, 444). What
changes is that it borrows the socket instead of creating one, listens through
streams instead of assigning callbacks, and never disposes it.

- [ ] **Step 1: Write the failing test**

Create `APP test/providers/realtime_fanout_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it passes**

Run: `flutter test test/providers/realtime_fanout_test.dart`
Expected: PASS — Task 1's streams already satisfy it. This test pins the
invariant that Step 3's rewiring must not break. If it fails, fix
`RealtimeConnection` before continuing.

- [ ] **Step 3: Rewire ChatScreen to borrow and subscribe**

In `APP lib/screens/chat/chat_screen.dart`, add a subscription list beside
`_flameSocket` (needs `dart:async`):

```dart
  final List<StreamSubscription<void>> _realtimeSubs = [];
```

and replace `_connectFlameSocket()`'s body:

```dart
  /// Subscribes this thread to the app-level realtime connection.
  ///
  /// It used to construct its own [FlameSocketService], which meant two sockets
  /// per user whenever a chat was open: the server re-checks blocks on every
  /// delivery, so the duplicate doubled that lookup and the presence fan-out
  /// for nothing. The socket is still held in [_flameSocket] because this
  /// screen emits through it (typing, read receipts) — but it does not own it
  /// and must never dispose it.
  ///
  /// Subscribing through streams rather than assigning the socket's callbacks
  /// matters: those fields are single-assignment, so assigning them here would
  /// silently steal every push from the conversation list and freeze the unread
  /// badge for other threads while this one is open.
  void _connectFlameSocket() {
    if (!EnvConfig.current.chatEnabled) return;

    final conn = ref.read(realtimeConnectionProvider);
    final socket = conn.socket;
    if (socket == null) return;
    _flameSocket = socket;

    _realtimeSubs.addAll([
      conn.messageNew.listen((e) => _onSocketMessageNew(e.message, e.conversationId)),
      conn.messageEdited.listen((e) => _onSocketMessageEdited(e.message, e.conversationId)),
      conn.messageDeleted.listen((e) => _onSocketMessageDeleted(e.message, e.conversationId)),
      conn.typing.listen((e) => _onSocketTyping(e.fromUserId, e.conversationId)),
      conn.stopTyping.listen((e) => _onSocketStopTyping(e.fromUserId, e.conversationId)),
      conn.presence.listen((e) => _onSocketPresence(e.userId, e.online)),
      conn.presenceBulk.listen(_onSocketPresenceBulk),
    ]);
  }
```

The existing `_onSocket*` handlers already filter on
`conversationId != widget.conversation.id` and check `mounted`, so they need no
change.

- [ ] **Step 4: Keep the badge honest for the open thread**

The conversation list is also subscribed, so a push for the thread the user is
reading increments the badge for a conversation that is on screen. Inside
`_onSocketMessageNew`, after the message is appended, clear it:

```dart
    // This thread is open and being read, so the server-side unread bump is
    // already stale for us. `clearUnread` is local-only; the REST mark-read
    // that tells the server runs on its own path.
    ref.read(conversationsProvider.notifier).clearUnread(widget.conversation.id);
```

- [ ] **Step 5: Do not dispose the shared socket**

In `dispose()` (line ~90), the `emitStopTyping` call stays — it uses the borrowed
socket, which is still alive. Replace `_flameSocket?.dispose();` with:

```dart
    // The connection is app-level and outlives this screen: cancel our
    // subscriptions instead of disposing it. Disposing it here would kill the
    // conversation list's realtime and the unread badge along with the chat.
    for (final s in _realtimeSubs) {
      s.cancel();
    }
    _realtimeSubs.clear();
    _flameSocket = null;
```

- [ ] **Step 6: Run the whole app suite**

Run: `flutter test && flutter analyze`
Expected: all pass, zero analyzer errors.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/chat/chat_screen.dart test/providers/realtime_fanout_test.dart
git commit -m "feat(realtime): ChatScreen borrows the app socket instead of opening a second"
```

---

### Task 5: Widen the Message model for media

**Files:**
- Modify: `flame/models/Message.js`
- Modify: `flame/services/chatService.js` (`toMessage`)
- Test: `flame/__tests__/messageMedia.test.js`

**Interfaces:**
- Produces: `Message.messageType` accepts `'text' | 'image' | 'video' | 'audio' | 'voice'`; new fields `mediaUrl`, `mediaKey`, `thumbnailUrl`, `durationSeconds`, `mediaWidth`, `mediaHeight`; `toMessage` emits `image_url`, `video_url`, `audio_url`, `media_info` — **the exact keys `APP lib/models/message.dart` already parses**

**The duration unit is seconds, not milliseconds.** `message_bubble.dart:418`
declares `String _formatDuration(int seconds)`, and `chat_service.dart` sends the
multipart field as `duration` in seconds. `MediaInfo.fromJson` reads
`json['duration']`, `json['width']`, `json['height']`, `json['thumbnail_url']`,
`json['file_size']`, `json['mime_type']` — those key names are the contract.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/messageMedia.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const dbHelper = require('./helpers/db');

async function setup() {
  await dbHelper.start();
  ['../db', '../models/Message'].forEach(p => {
    try { delete require.cache[require.resolve(p)]; } catch {}
  });
  const { connect } = require('../db');
  await connect();
  return require('../models/Message');
}

const teardown = (t) => t.after(async () => {
  const { close } = require('../db');
  await close();
  await dbHelper.stop();
});

test('every media kind is an accepted messageType', async (t) => {
  const Message = await setup();
  teardown(t);

  for (const kind of ['text', 'image', 'video', 'audio', 'voice']) {
    const m = await Message.create({
      conversationId: 'c1', sender: 'a', receiver: 'b', messageType: kind,
    });
    assert.equal(m.messageType, kind);
  }
});

test('an unknown messageType is still rejected', async (t) => {
  const Message = await setup();
  teardown(t);

  await assert.rejects(() => Message.create({
    conversationId: 'c1', sender: 'a', receiver: 'b', messageType: 'hologram',
  }));
});

test('media fields default to null so text messages stay unchanged', async (t) => {
  const Message = await setup();
  teardown(t);

  const m = await Message.create({
    conversationId: 'c1', sender: 'a', receiver: 'b', text: 'hi',
  });
  assert.equal(m.messageType, 'text');
  assert.equal(m.mediaUrl, null);
  assert.equal(m.thumbnailUrl, null);
  assert.equal(m.durationSeconds, null);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Projects/BananaTalk/backend && node --test flame/__tests__/messageMedia.test.js`
Expected: FAIL — `messageType` enum rejects `'image'`

- [ ] **Step 3: Widen the model**

In `flame/models/Message.js`, change the `messageType` line and add the media
fields directly beneath it:

```js
    messageType: {
      type: String,
      enum: ['text', 'image', 'video', 'audio', 'voice'],
      default: 'text',
    },
    // Media payload. Null on text messages, which is every message that
    // existed before this shipped — no migration needed.
    mediaUrl: { type: String, default: null },
    // S3 key kept alongside the URL so the object can be deleted later without
    // parsing it back out of the URL, which userService.deletePhoto has to do.
    mediaKey: { type: String, default: null },
    thumbnailUrl: { type: String, default: null },
    // Seconds, because that is the unit the shipped app sends and renders
    // (`_formatDuration(int seconds)` in message_bubble.dart). Do not switch it
    // to milliseconds without changing the app in the same release.
    durationSeconds: { type: Number, default: null },
    mediaWidth: { type: Number, default: null },
    mediaHeight: { type: Number, default: null },
```

- [ ] **Step 4: Serialise to the keys the app already parses**

In `flame/services/chatService.js`'s `toMessage`, add the media keys. The app's
`Message.fromJson` reads `image_url`, `video_url`, `audio_url` and `media_info` —
use exactly those:

```js
    image_url: m.messageType === 'image' ? m.mediaUrl : null,
    video_url: m.messageType === 'video' ? m.mediaUrl : null,
    audio_url: (m.messageType === 'audio' || m.messageType === 'voice')
      ? m.mediaUrl
      : null,
    media_info: m.mediaUrl
      ? {
          thumbnail_url: m.thumbnailUrl,
          duration: m.durationSeconds,
          width: m.mediaWidth,
          height: m.mediaHeight,
        }
      : null,
```

- [ ] **Step 5: Run test to verify it passes**

Run: `node --test flame/__tests__/messageMedia.test.js`
Expected: PASS — 3 tests

- [ ] **Step 6: Run the neighbouring chat tests**

Run: `node --test flame/__tests__/conversations.test.js`
Then: `node --test flame/__tests__/message_edit_delete.test.js`
Expected: both pass — `toMessage` is shared, so a serialisation change can break them.

- [ ] **Step 7: Commit**

```bash
git add flame/models/Message.js flame/services/chatService.js flame/__tests__/messageMedia.test.js
git commit -m "feat(chat): widen Message for media kinds and serialise the app's keys"
```

---

### Task 6: Media upload service

**Files:**
- Create: `flame/services/mediaService.js`
- Test: `flame/__tests__/mediaService.test.js`

**Interfaces:**
- Consumes: `flame/utils/s3.js` → `uploadBuffer(buffer, key, contentType) -> url`, `deleteObject(key)`
- Produces: `mediaService.storeMessageMedia(conversationId, kind, file) -> { url, key }`, and `mediaService.LIMITS` — a map of kind → `{ types: Set<string>, maxBytes: number }`

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/mediaService.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');

// The s3 module throws at load without these, and reads them at import time.
process.env.FLAME_SPACES_BUCKET = 'test-bucket';
process.env.SPACES_ENDPOINT = 'sfo3.digitaloceanspaces.com';
process.env.DO_SPACES_KEY = 'k';
process.env.DO_SPACES_SECRET = 's';

const S3 = require.resolve('../utils/s3');
const SVC = require.resolve('../services/mediaService');

function loadWithStubbedS3(onUpload) {
  const real = require.cache[S3];
  require.cache[S3] = {
    id: S3, filename: S3, loaded: true,
    exports: {
      uploadBuffer: async (buffer, key, contentType) => {
        onUpload({ buffer, key, contentType });
        return `https://cdn.example.com/${key}`;
      },
      deleteObject: async () => {},
      bucket: 'test-bucket',
    },
  };
  delete require.cache[SVC];
  const svc = require(SVC);
  return {
    svc,
    restore() {
      if (real) require.cache[S3] = real; else delete require.cache[S3];
      delete require.cache[SVC];
    },
  };
}

const file = (mimetype, size = 1024) => ({
  mimetype, size, buffer: Buffer.alloc(size), originalname: 'x',
});

test('stores an image and returns both the url and the key', async () => {
  let seen;
  const { svc, restore } = loadWithStubbedS3((u) => { seen = u; });
  try {
    const out = await svc.storeMessageMedia('c1', 'image', file('image/jpeg'));
    assert.ok(out.url.startsWith('https://'));
    assert.ok(out.key.includes('c1'), 'the key should be scoped to the conversation');
    assert.equal(seen.contentType, 'image/jpeg');
  } finally { restore(); }
});

test('rejects a MIME type the kind does not allow', async () => {
  const { svc, restore } = loadWithStubbedS3(() => {});
  try {
    await assert.rejects(
      () => svc.storeMessageMedia('c1', 'image', file('application/zip')),
      (e) => e.status === 422,
    );
  } finally { restore(); }
});

test('rejects a file over the kind limit', async () => {
  const { svc, restore } = loadWithStubbedS3(() => {});
  try {
    const tooBig = file('image/jpeg', svc.LIMITS.image.maxBytes + 1);
    await assert.rejects(
      () => svc.storeMessageMedia('c1', 'image', tooBig),
      (e) => e.status === 422,
    );
  } finally { restore(); }
});

test('video is allowed to be larger than an image', async () => {
  const { svc, restore } = loadWithStubbedS3(() => {});
  try {
    assert.ok(svc.LIMITS.video.maxBytes > svc.LIMITS.image.maxBytes);
  } finally { restore(); }
});

test('a missing file is a validation error, not a crash', async () => {
  const { svc, restore } = loadWithStubbedS3(() => {});
  try {
    await assert.rejects(
      () => svc.storeMessageMedia('c1', 'image', null),
      (e) => e.status === 422,
    );
  } finally { restore(); }
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/mediaService.test.js`
Expected: FAIL — `Cannot find module '../services/mediaService'`

- [ ] **Step 3: Write the service**

Create `flame/services/mediaService.js`:

```js
const crypto = require('crypto');
const s3 = require('../utils/s3');
const { ValidationError } = require('../utils/errors');

// Per-kind limits rather than one global cap: an image is not a video, and a
// single 50MB ceiling would let someone upload a 50MB "avatar".
const LIMITS = {
  image: { types: new Set(['image/jpeg', 'image/png', 'image/webp']), maxBytes: 10 * 1024 * 1024 },
  video: { types: new Set(['video/mp4', 'video/quicktime']), maxBytes: 50 * 1024 * 1024 },
  audio: { types: new Set(['audio/mpeg', 'audio/mp4', 'audio/aac']), maxBytes: 20 * 1024 * 1024 },
  voice: { types: new Set(['audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/ogg']), maxBytes: 10 * 1024 * 1024 },
};

const EXT = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp',
  'video/mp4': 'mp4', 'video/quicktime': 'mov',
  'audio/mpeg': 'mp3', 'audio/mp4': 'm4a', 'audio/aac': 'aac', 'audio/ogg': 'ogg',
};

// Stores one message attachment and returns its public URL plus the S3 key.
//
// The key is returned alongside the URL so a later delete does not have to
// reverse-engineer the path out of the URL, which userService.deletePhoto is
// currently forced to do.
async function storeMessageMedia(conversationId, kind, file) {
  const limit = LIMITS[kind];
  if (!limit) throw new ValidationError(`unsupported media kind: ${kind}`);
  if (!file) throw new ValidationError(`${kind} file is required`);

  if (!limit.types.has(file.mimetype)) {
    throw new ValidationError(
      `${kind} must be one of: ${[...limit.types].join(', ')}`,
    );
  }
  if (file.size > limit.maxBytes) {
    throw new ValidationError(
      `${kind} must be under ${Math.floor(limit.maxBytes / (1024 * 1024))}MB`,
    );
  }

  const id = crypto.randomUUID();
  const ext = EXT[file.mimetype] || 'bin';
  const key = `conversations/${conversationId}/${kind}/${id}.${ext}`;
  const url = await s3.uploadBuffer(file.buffer, key, file.mimetype);

  return { url, key };
}

module.exports = { storeMessageMedia, LIMITS };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test flame/__tests__/mediaService.test.js`
Expected: PASS — 5 tests

- [ ] **Step 5: Commit**

```bash
git add flame/services/mediaService.js flame/__tests__/mediaService.test.js
git commit -m "feat(chat): add media upload service with per-kind limits"
```

---

### Task 7: Media message routes

**Files:**
- Modify: `flame/services/chatService.js` (add `sendMediaMessage`)
- Modify: `flame/controllers/chatController.js`
- Modify: `flame/routes/conversations.js`
- Test: `flame/__tests__/mediaMessages.test.js`

**Interfaces:**
- Consumes: `mediaService.storeMessageMedia` (Task 6), `Message` media fields (Task 5), `visibility.assertCanInteract`, `matchService.isEndedBetween`
- Produces: `POST /conversations/:id/messages/{image,video,audio,voice}` — multipart, file field named for the kind, plus optional text fields `reply_to_id`, `duration` (seconds), and for video `width` / `height`

**Read `APP lib/services/chat_service.dart:100-200` before writing this.** The
shipped app sends exactly: `image` (+ `reply_to_id`), `video` (+ `duration`,
`width`, `height`, `reply_to_id`), `audio` and `voice` (+ `duration`,
`reply_to_id`). It sends **no thumbnail file** — the video route accepts one
anyway so a later app release can add it without a backend change, but no test
should assume the client supplies it.

**The contract is fixed by the shipped app** (`APP lib/services/chat_service.dart`):
paths and multipart field names above are not negotiable.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/mediaMessages.test.js`. Model the setup on
`flame/__tests__/conversations.test.js`, applying all three standing corrections.
Cover:

```js
// 1. POST /conversations/:id/messages/image with an attached jpeg returns 201
//    and a Message whose image_url is set and messageType is 'image'.
// 2. The same route rejects a blocked pair with 403 — the guard must be on the
//    media path, not only on text.
// 3. The same route rejects an ended match with 403.
// 4. A non-participant gets 404.
// 5. An oversize or wrong-MIME upload returns 422.
// 6. POST .../messages/voice with duration=12 sets messageType 'voice',
//    populates audio_url, and returns media_info.duration === 12.
// 7. A voice note sent WITHOUT duration still succeeds, with a null duration.
// 8. A garbage duration ('abc') stores null rather than failing with a CastError.
```

Attach files with supertest's `.attach('image', Buffer.from(...), {filename, contentType})`.
Stub `flame/utils/s3.js` via the require-cache technique from Task 6 so no real
upload happens.

> Write these as real assertions with real request bodies — the comment block
> above is the checklist, not the test. A test that only asserts a status code
> without checking the stored message is not enough for cases 1 and 6.

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/mediaMessages.test.js`
Expected: FAIL — 404, routes not mounted

- [ ] **Step 3: Add the service method**

In `flame/services/chatService.js`, beside `sendMessage`:

```js
// Sends a media message. Deliberately mirrors sendMessage's guard order —
// participation, then block, then ended-match — because a media route that
// skips them would reopen exactly the holes Phase A closed.
async function sendMediaMessage(userId, conversationId, kind, file, { replyTo, thumbnail, duration, width, height } = {}) {
  const conv = await _findConversation(conversationId);
  if (!conv.participants.includes(userId)) throw new NotFoundError('conversation not found');

  const receiver = conv.participants.find((p) => p !== userId);
  await visibility.assertCanInteract(userId, receiver);
  if (await matchService.isEndedBetween(userId, receiver)) {
    throw new ForbiddenError('this match has ended');
  }

  const stored = await mediaService.storeMessageMedia(conversationId, kind, file);
  const thumb = thumbnail
    ? await mediaService.storeMessageMedia(conversationId, 'image', thumbnail)
    : null;

  const msg = await Message.create({
    conversationId,
    sender: userId,
    receiver,
    messageType: kind,
    mediaUrl: stored.url,
    mediaKey: stored.key,
    thumbnailUrl: thumb ? thumb.url : null,
    // Client-supplied and untrusted: the server does not probe the file. A
    // voice note with no duration renders as a bare play button — a degraded
    // UI, not a broken one, and worth far less than running ffmpeg on the API
    // box. Multipart text fields arrive as strings, so coerce here.
    durationSeconds: _int(duration),
    mediaWidth: _int(width),
    mediaHeight: _int(height),
    replyTo: replyTo || null,
  });

  await _bumpConversation(conv, receiver, `[${kind}]`);
  return toMessage(msg);
}
```

> `_findConversation`, `_bumpConversation` and the exact unread-increment code
> already exist in this file under whatever names `sendMessage` uses — read it
> and reuse them rather than duplicating. If `sendMessage` inlines that logic,
> extract it so both paths share one implementation.

with a small helper beside it:

```js
// Multipart text fields are always strings, and a client can send anything.
// Anything not a finite non-negative number becomes null rather than NaN,
// which Mongoose would reject with an unhelpful CastError.
function _int(value) {
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? Math.round(n) : null;
}
```

Require `mediaService`, `matchService` and `ForbiddenError` at the top if not
already present, and export `sendMediaMessage`.

- [ ] **Step 4: Add the controller and routes**

In `flame/controllers/chatController.js`:

```js
async function sendMedia(req, res) {
  const kind = req.mediaKind; // set by the route
  const file = req.files ? (req.files[kind] || [])[0] : req.file;
  const thumbnail = req.files ? (req.files.thumbnail || [])[0] : null;

  const message = await chatService.sendMediaMessage(
    req.user.id, req.params.id, kind, file,
    {
      replyTo: req.body.reply_to_id,
      thumbnail,
      duration: req.body.duration,
      width: req.body.width,
      height: req.body.height,
    },
  );
  res.status(201).json({ success: true, data: message });
}
```

In `flame/routes/conversations.js`, add a multer instance and the four routes.
Video uses `.fields` because it may carry a thumbnail; the rest use `.single`:

```js
const multer = require('multer');
const upload = multer({
  storage: multer.memoryStorage(),
  // Hard ceiling at the multer layer; per-kind limits are enforced in
  // mediaService so the error is a 422 with a useful message.
  limits: { fileSize: 50 * 1024 * 1024 },
});

const withKind = (kind) => (req, _res, next) => { req.mediaKind = kind; next(); };

router.post('/:id/messages/image', auth, validate.params(idParam),
  withKind('image'), upload.single('image'), asyncHandler(ctrl.sendMedia));

router.post('/:id/messages/voice', auth, validate.params(idParam),
  withKind('voice'), upload.single('voice'), asyncHandler(ctrl.sendMedia));

router.post('/:id/messages/audio', auth, validate.params(idParam),
  withKind('audio'), upload.single('audio'), asyncHandler(ctrl.sendMedia));

router.post('/:id/messages/video', auth, validate.params(idParam),
  withKind('video'),
  upload.fields([{ name: 'video', maxCount: 1 }, { name: 'thumbnail', maxCount: 1 }]),
  asyncHandler(ctrl.sendMedia));
```

- [ ] **Step 5: Run test to verify it passes**

Run: `node --test flame/__tests__/mediaMessages.test.js`
Expected: PASS — all cases

- [ ] **Step 6: Confirm text sending still works**

Run: `node --test flame/__tests__/conversations.test.js`
Then: `node --test flame/__tests__/unmatchEnforcement.test.js`
Expected: both pass — you refactored shared helpers out of `sendMessage`.

- [ ] **Step 7: Commit**

```bash
git add flame/services/chatService.js flame/controllers/chatController.js \
        flame/routes/conversations.js flame/__tests__/mediaMessages.test.js
git commit -m "feat(chat): add media message routes the app already calls"
```

---

### Task 8: Conversation controls — model and routes

**Files:**
- Modify: `flame/models/Conversation.js`
- Create: `flame/services/conversationControlsService.js`
- Modify: `flame/controllers/chatController.js`, `flame/routes/conversations.js`
- Test: `flame/__tests__/conversationControls.test.js`

**Interfaces:**
- Produces:
  - `Conversation.mutedBy: [{ user, mutedUntil, mutedAt }]`, `pinnedBy: [{ user, messageId, pinnedAt }]`, `archivedBy: [{ user, archivedAt }]`
  - `conversationControlsService.mute(userId, conversationId, durationMs)`, `unmute`, `pinMessage(userId, conversationId, messageId)`, `unpinMessage`, `isMutedFor(conversationId, userId) -> boolean`
  - Routes: `POST/DELETE /conversations/:id/mute`, `POST /conversations/:id/pin`, `DELETE /conversations/:id/pin/:messageId`

**Contract fixed by the shipped app:** those four paths, with `{ message_id }` in
the pin body and an optional `{ duration }` in the mute body.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/conversationControls.test.js` covering:

```js
// 1. POST /conversations/:id/mute mutes for the caller only — the other
//    participant's view is unaffected (assert on the stored arrays).
// 2. DELETE /conversations/:id/mute unmutes.
// 3. Muting does NOT hide the conversation and does NOT stop unread counting.
// 4. POST /conversations/:id/pin with { message_id } pins for the caller only.
// 5. DELETE /conversations/:id/pin/:messageId unpins.
// 6. A non-participant gets 404 on all four.
// 7. Pinning a message that belongs to another conversation is a 422.
```

Apply all three standing corrections. Write real assertions, not a checklist.

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/conversationControls.test.js`
Expected: FAIL — 404, routes not mounted

- [ ] **Step 3: Add the model fields**

In `flame/models/Conversation.js`, after `unreadCount`:

```js
    // Per-user, not per-conversation: muting, pinning and archiving are one
    // participant's choice and must not change what the other sees. Shape
    // copied from BananaTalk's Conversation, which is proven in production.
    mutedBy: {
      type: [{
        user: { type: String, required: true },
        mutedUntil: { type: Date, default: null },  // null = indefinite
        mutedAt: { type: Date, default: Date.now },
      }],
      default: [],
    },
    pinnedBy: {
      type: [{
        user: { type: String, required: true },
        messageId: { type: String, required: true },
        pinnedAt: { type: Date, default: Date.now },
      }],
      default: [],
    },
    archivedBy: {
      type: [{
        user: { type: String, required: true },
        archivedAt: { type: Date, default: Date.now },
      }],
      default: [],
    },
```

- [ ] **Step 4: Write the service**

Create `flame/services/conversationControlsService.js` with `mute`, `unmute`,
`pinMessage`, `unpinMessage` and `isMutedFor`. Each must:

- load the conversation and 404 if the caller is not a participant (use the same
  helper `chatService` uses)
- guard against duplicates with an explicit `$ne` filter, not `$addToSet` —
  these are subdocuments carrying timestamps, so `$addToSet` will not dedupe
  (the same trap Phase A's `blockService` hit)
- for `pinMessage`, verify the message belongs to that conversation and throw
  `ValidationError` if not

- [ ] **Step 5: Add the controller and routes**

Add four handlers to `flame/controllers/chatController.js` and mount:

```js
router.post('/:id/mute', auth, validate.params(idParam),
  validate.body(muteSchema), asyncHandler(ctrl.muteConversation));
router.delete('/:id/mute', auth, validate.params(idParam),
  asyncHandler(ctrl.unmuteConversation));
router.post('/:id/pin', auth, validate.params(idParam),
  validate.body(pinSchema), asyncHandler(ctrl.pinMessage));
router.delete('/:id/pin/:messageId', auth, validate.params(pinParams),
  asyncHandler(ctrl.unpinMessage));
```

with zod schemas following the file's existing style:

```js
const muteSchema = z.object({ duration: z.number().int().positive().optional() });
const pinSchema = z.object({ message_id: objectId });
const pinParams = z.object({ id: objectId, messageId: objectId });
```

- [ ] **Step 6: Run test to verify it passes**

Run: `node --test flame/__tests__/conversationControls.test.js`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add flame/models/Conversation.js flame/services/conversationControlsService.js \
        flame/controllers/chatController.js flame/routes/conversations.js \
        flame/__tests__/conversationControls.test.js
git commit -m "feat(chat): add per-user mute and pin"
```

---

### Task 9: Mute suppresses push; archive filters the list

**Files:**
- Modify: `flame/services/pushService.js` (or wherever the new-message push is sent — read first)
- Modify: `flame/services/chatService.js` (`listConversations`)
- Test: `flame/__tests__/conversationControlsEffects.test.js`

**Interfaces:**
- Consumes: `conversationControlsService.isMutedFor` (Task 8)
- Produces: no new exports — behaviour only

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/conversationControlsEffects.test.js` covering:

```js
// 1. listConversations excludes a conversation the caller archived, and still
//    includes it for the other participant.
// 2. Archiving does not disturb the existing block / ended-match exclusions —
//    seed one archived, one blocked, one ended, one normal, and assert only the
//    normal one comes back.
// 3. countDocuments and find still agree: pagination.total matches the returned
//    length when everything else is filtered out.
// 4. A muted conversation still appears in the list and still accrues unread.
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/conversationControlsEffects.test.js`
Expected: FAIL — archived conversations still returned

- [ ] **Step 3: Filter archived conversations**

In `chatService.listConversations`, the filter already excludes blocked ids and
ended-match partners via `$nin` on `participants`. Add archive as a separate
condition on the conversation itself, not the participants:

```js
  // Archive is per-user, so it filters on this conversation's own array rather
  // than on the participant ids the block/ended-match exclusions use.
  filter['archivedBy.user'] = { $ne: userId };
```

Apply it before `countDocuments`, so count and find continue to share one filter.

- [ ] **Step 4: Suppress push for muted conversations**

Read `flame/services/pushService.js` and find where a new-message notification is
sent. Guard it:

```js
  // A muted conversation still appears and still accrues unread count — mute
  // only silences the notification.
  if (await conversationControls.isMutedFor(conversationId, receiverId)) return;
```

If push is dispatched from `chatController` rather than `pushService`, put the
guard at that call site instead and say which you chose in your report.

- [ ] **Step 5: Run test to verify it passes**

Run: `node --test flame/__tests__/conversationControlsEffects.test.js`
Expected: PASS

- [ ] **Step 6: Confirm the Phase A exclusions still hold**

Run: `node --test flame/__tests__/blockEnforcement.test.js`
Then: `node --test flame/__tests__/unmatchEnforcement.test.js`
Expected: both pass. If either fails, your archive filter has disturbed the
block or ended-match exclusion — fix the filter, not the test.

- [ ] **Step 7: Commit**

```bash
git add flame/services/chatService.js flame/services/pushService.js \
        flame/__tests__/conversationControlsEffects.test.js
git commit -m "feat(chat): mute silences push, archive filters the list"
```

---

### Task 10: End-to-end verification

**Files:** none — a manual gate.

- [ ] **Step 1: Run the full backend suite**

```bash
cd ~/Projects/BananaTalk/backend
node --test --test-concurrency=1 flame/__tests__/
```
Expected: every test passes. Use `--test-concurrency=1`; parallel runs have hung
on this suite.

- [ ] **Step 2: Run the full app suite**

```bash
cd ~/Desktop/Flame/flame_front_app
flutter test && flutter analyze
```
Expected: all pass, zero analyzer errors.

- [ ] **Step 3: Check for legacy indexes BEFORE deploying**

```bash
cd ~/Projects/BananaTalk/backend
node flame/scripts/drop-legacy-indexes.js
```
Expected: `nothing to drop`. Phase A shipped broken because `flame_db` held
collections from an earlier schema whose unique indexes no test could see. This
phase adds no new collections, but the check is cheap and the failure mode is
invisible.

- [ ] **Step 4: Deploy**

```bash
# on the server
cd /home/language_exchange_backend_application && git pull && pm2 restart language-app
```

Note: pushing to `main` triggers this automatically via
`.github/workflows/deploy.yml`.

- [ ] **Step 5: Verify realtime with two accounts**

1. Sign in as A and B on two devices.
2. B sends A a message while **A is on the Discover tab, not in the chat**.
3. A's Chat tab badge increments **without a refresh** — this is B1's whole point.
4. A opens the conversation: the message is there, and the badge clears.
5. A backgrounds the app for longer than the access-token lifetime, returns, and
   B sends again — A still receives it (the reconnect picked up a fresh token).
6. A logs out and back in as a different user: no messages from A's session leak.

- [ ] **Step 6: Verify media and controls**

1. Send an image, a voice note, and a video from A to B — each renders.
2. Block B, then attempt an image send — it must fail with 403, not upload.
3. Mute the conversation — messages still arrive and still count as unread, but
   no push notification fires.
4. Pin a message — it stays pinned for the pinner and is unaffected for the other.
