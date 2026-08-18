// Regression test for the bug B1 exists to fix: ChatScreen used to open its
// own FlameSocketService (gated on ApiClient().accessToken, which is null in
// any test/unit context that hasn't gone through real login) instead of
// borrowing the app-level RealtimeConnection. That meant an open ChatScreen
// never reacted to a push delivered on the shared connection, and — had it
// instead assigned the shared socket's single-assignment callback fields
// directly — it would have stolen every push from the conversation list.
//
// This test builds the shared connection with an injected fake socket,
// subscribes a "list-level" listener the way main_shell does, then mounts
// ChatScreen through the real realtimeConnectionProvider. It requires no
// live ApiClient and touches no network: chatServiceProvider, UserService
// and ConversationsNotifier are all faked/seeded.
//
// Two further tests below pin a code-review finding on the fix itself:
// ChatScreen must cache the *connection*, not its socket, because the socket
// can be null at mount (not yet connected) or swapped out from under a
// cached reference by a mid-session token refresh (RealtimeConnection.start
// disposes the old socket and builds a new one).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/chat_provider.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/providers/user_provider.dart';
import 'package:flame/screens/chat/chat_screen.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/services/flame_socket_service.dart';
import 'package:flame/services/user_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSocket extends FlameSocketService {
  _FakeSocket(String token) : super(token: token);
  bool disposed = false;
  final List<String> typingEmittedTo = [];
  @override
  void connect() {}
  @override
  void dispose() => disposed = true;
  @override
  bool get isConnected => !disposed;
  @override
  void emitTyping(String to, String conversationId) => typingEmittedTo.add(to);
}

// getMessages is the only chatService method ChatScreen calls on init;
// failing it immediately keeps _messages empty without touching a network.
class _FakeChatService extends ChatService {
  @override
  Future<ServiceResult<MessagesResult>> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
    String? before,
  }) async {
    return ServiceResult.failure('no network in tests');
  }
}

// Never called (UserService.getCurrentUser is only invoked by loadUser,
// which this test never triggers) — exists only so CurrentUserNotifier has
// something to hold that isn't a real, network-backed UserService.
class _FakeUserService extends UserService {}

// Seeded with the conversation carrying no messages, so
// ConversationsNotifier.markAsRead (fired by _onSocketMessageNew) finds the
// conversation and short-circuits on an empty unread list instead of
// throwing "Conversation not found" against the default empty/loading state.
class _SeededConversations extends ConversationsNotifier {
  _SeededConversations(List<Conversation> initial) : super(ChatService()) {
    state = AsyncValue.data(initial);
  }
}

Conversation _conversation(String id, String otherUserId) =>
    Conversation.fromJson({
      'id': id,
      'other_user': {'id': otherUserId, 'name': 'Other'},
      'last_message_at': '2026-08-17T00:00:00.000Z',
    });

Message _msg(String id, String senderId) => Message.fromJson({
  'id': id,
  'sender_id': senderId,
  'text': 'live push',
  'type': 'text',
  'created_at': '2026-08-17T00:01:00.000Z',
});

User _me() => User.fromJson({
  'id': 'me',
  'name': 'Me',
  'age': 30,
  'bio': '',
  'interests': <dynamic>[],
  'gender': 'male',
  'photos': [],
});

// Shared boilerplate for every test below: same fakes/seeds, same
// localization wiring (MessageBubble needs AppLocalizations), differing only
// in which RealtimeConnection and Conversation are plugged in.
Future<void> _pumpChatScreen(
  WidgetTester tester, {
  required RealtimeConnection conn,
  required Conversation conversation,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatServiceProvider.overrideWithValue(_FakeChatService()),
        currentUserProvider.overrideWith(
          (ref) => CurrentUserNotifier(_FakeUserService())..setUser(_me()),
        ),
        conversationsProvider.overrideWith(
          (ref) => _SeededConversations([conversation]),
        ),
        realtimeConnectionProvider.overrideWithValue(conn),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: kSupportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ChatScreen(conversation: conversation),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'a push on the shared connection reaches an open ChatScreen, and the '
    'list-level listener still receives it too',
    (tester) async {
      late _FakeSocket socket;
      final conn = RealtimeConnection(createSocket: (t) {
        socket = _FakeSocket(t);
        return socket;
      });
      addTearDown(conn.dispose);
      conn.start('token-a');

      // Mimics the conversation list: already subscribed before this screen
      // ever opens, exactly the arrangement main_shell sets up.
      final listSeen = <String>[];
      conn.messageNew.listen((e) => listSeen.add(e.message.id));

      final conversation = _conversation('c1', 'u1');

      await _pumpChatScreen(tester, conn: conn, conversation: conversation);
      await tester.pump();
      await tester.pump();

      expect(find.text('live push'), findsNothing);

      socket.onMessageNew!(_msg('m1', 'u1'), 'c1');
      await tester.pump();
      await tester.pump();

      expect(
        find.text('live push'),
        findsOneWidget,
        reason:
            'ChatScreen must receive pushes through the shared connection, '
            'not by opening a socket of its own gated on a live ApiClient token',
      );
      expect(
        listSeen,
        ['m1'],
        reason: 'the list-level listener must still see the push too',
      );
    },
  );

  testWidgets(
    'a mid-session token refresh does not silently kill emits from an open chat',
    (tester) async {
      // ApiClient's proactive refresh drives exactly this: RealtimeConnection
      // .start() with a new token disposes the old socket and builds a new
      // one. If ChatScreen cached the socket instead of the connection, its
      // emits would keep targeting the disposed instance.
      final sockets = <_FakeSocket>[];
      final conn = RealtimeConnection(createSocket: (t) {
        final s = _FakeSocket(t);
        sockets.add(s);
        return s;
      });
      addTearDown(conn.dispose);
      conn.start('token-a');

      final conversation = _conversation('c1', 'u1');
      await _pumpChatScreen(tester, conn: conn, conversation: conversation);
      await tester.pump();
      await tester.pump();

      // Force the reconnect.
      conn.start('token-b');
      expect(sockets, hasLength(2));
      expect(sockets[0].disposed, isTrue,
          reason: 'the pre-refresh socket is torn down by RealtimeConnection.start');

      // Trigger `emitTyping` via the real input, exactly as a typing user
      // would.
      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();

      expect(sockets[1].typingEmittedTo, ['u1'],
          reason: 'the emit must reach the socket that is live after the '
              'refresh, not the one RealtimeConnection already disposed');
      expect(sockets[0].typingEmittedTo, isEmpty,
          reason: 'the disposed pre-refresh socket must never be emitted to');
    },
  );

  testWidgets(
    'a screen mounted before the connection is up still receives a later push',
    (tester) async {
      // Covers the other half of the same defect: caching `conn.socket`
      // (nullable at mount) instead of `conn` itself would mean a screen
      // opened before the connection comes up never subscribes at all,
      // since `_connectFlameSocket` runs exactly once, from `initState`.
      late _FakeSocket socket;
      final conn = RealtimeConnection(createSocket: (t) {
        socket = _FakeSocket(t);
        return socket;
      });
      addTearDown(conn.dispose);
      // Deliberately not started yet: conn.socket is null at mount time.

      final conversation = _conversation('c1', 'u1');
      await _pumpChatScreen(tester, conn: conn, conversation: conversation);
      await tester.pump();
      await tester.pump();

      // The connection comes up after the screen already mounted.
      conn.start('token-a');

      socket.onMessageNew!(_msg('m1', 'u1'), 'c1');
      await tester.pump();
      await tester.pump();

      expect(
        find.text('live push'),
        findsOneWidget,
        reason: 'subscribing must not depend on a socket already existing '
            'at mount time',
      );
    },
  );

  // Critical: the app-level connection removed the only thing that used to
  // re-authenticate the socket. socket.io captures its auth token once and
  // replays it on every automatic reconnect, so after ApiClient's proactive
  // refresh the socket holds a token the handshake will reject forever —
  // and a refresh never touches authProvider, which is the only thing that
  // re-drove the connection. Opening a conversation was a refresh point
  // before B1 (the old code built a fresh socket from ApiClient().accessToken
  // on every mount) and has to remain one.
  testWidgets(
    'opening a chat re-authenticates the connection from the current token',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      await ApiClient().saveTokens(accessToken: 'live-token', refreshToken: 'r');
      addTearDown(() async {
        await ApiClient().clearTokens();
      });

      final sockets = <_FakeSocket>[];
      final conn = RealtimeConnection(createSocket: (t) {
        final s = _FakeSocket(t);
        sockets.add(s);
        return s;
      });
      addTearDown(conn.dispose);
      // Deliberately never started: this stands in for a connection whose
      // socket died on a token that has since been refreshed.

      await _pumpChatScreen(
        tester,
        conn: conn,
        conversation: _conversation('c1', 'u1'),
      );
      await tester.pump();

      expect(sockets, hasLength(1),
          reason: 'mounting a chat must bring the connection up on the token '
              'ApiClient holds now');
      expect(sockets.single.token, 'live-token');
      expect(conn.socket, isNotNull);
    },
  );
}
