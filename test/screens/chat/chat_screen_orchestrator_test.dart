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
import 'package:flame/screens/chat/conversation/chat_screen.dart';
import 'package:flame/screens/chat/error/chat_error_widget.dart';
import 'package:flame/screens/chat/header/chat_app_bar.dart';
import 'package:flame/screens/chat/message/messages_list.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/services/user_service.dart';

class _ThreadService extends ChatService {
  _ThreadService({this.fail = false});
  final bool fail;

  @override
  Future<ServiceResult<MessagesResult>> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
    String? before,
  }) async {
    if (fail) return ServiceResult.failure('offline');
    return ServiceResult.success(MessagesResult(messages: [
      Message.fromJson({
        'id': 'm1', 'sender_id': 'u1', 'text': 'hello',
        'created_at': '2026-08-18T10:00:00.000Z',
      }),
    ], hasMore: false));
  }

  @override
  Future<ServiceResult<List<PinnedMessage>>> getPinnedMessages(String id) async =>
      ServiceResult.success(const []);

  @override
  Future<ServiceResult<void>> markMessagesAsRead(String id) async =>
      ServiceResult.success(null);
}

class _FakeUserService extends UserService {
  @override
  Future<ServiceResult<User>> getCurrentUser() async =>
      ServiceResult.failure('not used');
}

class _SeededConversations extends ConversationsNotifier {
  _SeededConversations(List<Conversation> initial) : super(ChatService()) {
    state = AsyncValue.data(initial);
  }
}

User _me() => User.fromJson({'id': 'me', 'name': 'Me', 'photos': <dynamic>[]});

Conversation _conv() => Conversation.fromJson({
      'id': 'c1',
      'other_user': {'id': 'u1', 'name': 'Bea', 'photos': <dynamic>[]},
      'updated_at': '2026-08-18T10:00:00.000Z',
    });

Future<void> _pump(WidgetTester tester, {required ChatService service}) {
  final conversation = _conv();
  return tester.pumpWidget(ProviderScope(
    overrides: [
      chatServiceProvider.overrideWithValue(service),
      currentUserProvider.overrideWith(
        (ref) => CurrentUserNotifier(_FakeUserService())..setUser(_me()),
      ),
      conversationsProvider.overrideWith(
        (ref) => _SeededConversations([conversation]),
      ),
      realtimeConnectionProvider.overrideWithValue(RealtimeConnection()),
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
  ));
}

void main() {
  testWidgets('renders the header and the list, and loads the thread',
      (tester) async {
    await _pump(tester, service: _ThreadService());
    await tester.pumpAndSettle();

    expect(find.byType(ChatAppBar), findsOneWidget);
    expect(find.byType(ChatMessagesList), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('Bea'), findsOneWidget);
  });

  testWidgets('a failed load shows the error, not the say-hello prompt',
      (tester) async {
    await _pump(tester, service: _ThreadService(fail: true));
    await tester.pumpAndSettle();

    expect(find.byType(ChatErrorWidget), findsOneWidget);
    expect(find.textContaining('matched with'), findsNothing,
        reason: 'the whole point of the three-state split');
  });

  testWidgets('opening a thread starts no periodic timer', (tester) async {
    await _pump(tester, service: _ThreadService());
    await tester.pumpAndSettle();

    // A pending periodic timer fails the test at teardown. The 4-second REST
    // poll never once fired its body in either shipped env, because
    // realtimeEnabled is true in both — so it is gone entirely.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('every message row is keyed by its id', (tester) async {
    await _pump(tester, service: _ThreadService());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('m1')), findsOneWidget);
  });
}
