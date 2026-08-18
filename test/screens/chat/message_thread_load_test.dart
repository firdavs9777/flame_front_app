import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/screens/chat/chat_rows.dart';
import 'package:flame/screens/chat/state/message_thread_provider.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

Message m(String id, String text, String at) => Message.fromJson({
      'id': id, 'sender_id': 'u2', 'text': text, 'created_at': at,
    });

/// Serves canned pages and records the cursor it was asked for.
class PagingService extends ChatService {
  PagingService(this.pages);
  final List<MessagesResult> pages;
  final List<String?> cursors = [];
  int _call = 0;

  @override
  Future<ServiceResult<MessagesResult>> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
    String? before,
  }) async {
    cursors.add(before);
    if (_call >= pages.length) {
      return ServiceResult.success(MessagesResult(messages: [], hasMore: false));
    }
    return ServiceResult.success(pages[_call++]);
  }
}

class FailingService extends ChatService {
  @override
  Future<ServiceResult<MessagesResult>> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
    String? before,
  }) async =>
      ServiceResult.failure('offline');
}

MessageThreadNotifier notifierWith(ChatService service) => MessageThreadNotifier(
      conversationId: 'c1',
      service: service,
      connection: RealtimeConnection(),
    );

void main() {
  test('load stores messages oldest-first and derives rows', () async {
    // The server answers newest-first.
    final service = PagingService([
      MessagesResult(messages: [
        m('m3', 'third', '2026-08-18T12:00:00.000Z'),
        m('m2', 'second', '2026-08-18T11:00:00.000Z'),
        m('m1', 'first', '2026-08-18T10:00:00.000Z'),
      ], hasMore: true),
    ]);
    final n = notifierWith(service);

    await n.load();

    expect(n.state.messages.map((x) => x.id).toList(), ['m1', 'm2', 'm3']);
    expect(n.state.oldestId, 'm1');
    expect(n.state.hasMore, isTrue);
    expect(n.state.isLoadingInitial, isFalse);
    expect(n.state.error, isNull);
    expect(n.state.rows.length, buildChatRows(n.state.messages).length);
    expect(service.cursors, [null], reason: 'the newest page takes no cursor');
  });

  test('a failed load sets error and is NOT the empty state', () async {
    final n = notifierWith(FailingService());

    await n.load();

    expect(n.state.error, isNotNull);
    expect(n.state.messages, isEmpty);
    expect(n.state.isLoadingInitial, isFalse);
    expect(n.state.isEmpty, isFalse,
        reason: 'a network failure must never render "say hello" — that invites '
            'the user to greet a thread that failed to load');
  });

  test('an empty conversation is the empty state, not an error', () async {
    final n = notifierWith(
        PagingService([MessagesResult(messages: [], hasMore: false)]));

    await n.load();

    expect(n.state.error, isNull);
    expect(n.state.isEmpty, isTrue);
    expect(n.state.oldestId, isNull);
  });

  test('a retry after a failure clears the error', () async {
    final service = _FlakyOnce();
    final n = notifierWith(service);

    await n.load();
    expect(n.state.error, isNotNull);

    await n.load();
    expect(n.state.error, isNull);
    expect(n.state.messages.single.id, 'm1');
  });

  test('rows are reused when messages are unchanged', () async {
    final n = notifierWith(PagingService([
      MessagesResult(
          messages: [m('m1', 'a', '2026-08-18T10:00:00.000Z')], hasMore: false),
    ]));
    await n.load();

    final rowsBefore = n.state.rows;
    // A state change that does not touch messages must not rebuild rows.
    n.state = n.state.copyWith(isLoadingMore: true);

    expect(identical(n.state.rows, rowsBefore), isTrue);
  });
}

class _FlakyOnce extends ChatService {
  int _calls = 0;

  @override
  Future<ServiceResult<MessagesResult>> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
    String? before,
  }) async {
    if (_calls++ == 0) return ServiceResult.failure('offline');
    return ServiceResult.success(MessagesResult(
        messages: [m('m1', 'a', '2026-08-18T10:00:00.000Z')], hasMore: false));
  }
}
