import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/screens/chat/state/message_thread_provider.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

Message m(String id, String text, String at) => Message.fromJson({
      'id': id, 'sender_id': 'u2', 'text': text, 'created_at': at,
    });

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

/// Serves a good first page, then fails whenever [failNext] is set.
class FlakyService extends ChatService {
  bool failNext = false;
  final List<String?> cursors = [];

  @override
  Future<ServiceResult<MessagesResult>> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
    String? before,
  }) async {
    cursors.add(before);
    if (failNext) return ServiceResult.failure('offline');
    return ServiceResult.success(MessagesResult(messages: [
      m('m3', 'third', '2026-08-18T12:00:00.000Z'),
      m('m2', 'second', '2026-08-18T11:00:00.000Z'),
    ], hasMore: true));
  }
}

MessageThreadNotifier notifierWith(ChatService s) => MessageThreadNotifier(
    conversationId: 'c1', service: s, connection: RealtimeConnection());

List<MessagesResult> _twoPages() => [
      MessagesResult(messages: [
        m('m3', 'third', '2026-08-18T12:00:00.000Z'),
        m('m2', 'second', '2026-08-18T11:00:00.000Z'),
      ], hasMore: true),
      MessagesResult(messages: [
        m('m1', 'first', '2026-08-18T10:00:00.000Z'),
      ], hasMore: false),
    ];

void main() {
  test('loadMore prepends older messages and advances the cursor', () async {
    final service = PagingService(_twoPages());
    final n = notifierWith(service);

    await n.load();
    await n.loadMore();

    expect(n.state.messages.map((x) => x.id).toList(), ['m1', 'm2', 'm3']);
    expect(n.state.oldestId, 'm1');
    expect(n.state.hasMore, isFalse);
    expect(service.cursors, [null, 'm2'],
        reason: 'the second page is anchored to the oldest loaded id');
  });

  test('a push arriving mid-paging does not move the cursor', () async {
    final service = PagingService(_twoPages());
    final n = notifierWith(service);
    await n.load();

    // A newer message lands between the two page fetches. Under offset paging
    // this inflated messages.length and the next page skipped history.
    n.appendPushed(m('m9', 'live', '2026-08-18T13:00:00.000Z'));
    await n.loadMore();

    expect(service.cursors, [null, 'm2'],
        reason: 'the cursor is a message id, so a newer arrival cannot shift it');
    expect(n.state.messages.map((x) => x.id).toList(),
        ['m1', 'm2', 'm3', 'm9']);
  });

  test('a failed loadMore keeps messages and does not advance the cursor',
      () async {
    final service = FlakyService();
    final n = notifierWith(service);
    await n.load();
    final before = n.state.messages.map((x) => x.id).toList();

    service.failNext = true;
    await n.loadMore();

    expect(n.state.messages.map((x) => x.id).toList(), before);
    expect(n.state.oldestId, 'm2',
        reason: 'advancing past a page that never arrived loses history '
            'silently');
    expect(n.state.error, isNotNull);
    expect(n.state.isLoadingMore, isFalse);
  });

  test('loadMore is a no-op once the server says there is no more', () async {
    final service = PagingService([
      MessagesResult(
          messages: [m('m1', 'a', '2026-08-18T10:00:00.000Z')], hasMore: false),
    ]);
    final n = notifierWith(service);
    await n.load();

    await n.loadMore();
    await n.loadMore();

    expect(service.cursors, [null], reason: 'hasMore was false');
  });

  test('an empty older page ends paging without clearing the thread', () async {
    final service = PagingService([
      MessagesResult(messages: [
        m('m2', 'b', '2026-08-18T11:00:00.000Z'),
      ], hasMore: true),
      MessagesResult(messages: [], hasMore: false),
    ]);
    final n = notifierWith(service);
    await n.load();

    await n.loadMore();

    expect(n.state.messages.single.id, 'm2');
    expect(n.state.hasMore, isFalse);
    expect(n.state.oldestId, 'm2');
  });

  test('appendPushed ignores a message already present', () async {
    final n = notifierWith(PagingService([
      MessagesResult(
          messages: [m('m1', 'a', '2026-08-18T10:00:00.000Z')], hasMore: false),
    ]));
    await n.load();

    n.appendPushed(m('m1', 'a', '2026-08-18T10:00:00.000Z'));

    expect(n.state.messages.length, 1);
  });

  test('applyUpdate replaces in place and ignores unknown ids', () async {
    final n = notifierWith(PagingService([
      MessagesResult(messages: [
        m('m1', 'before', '2026-08-18T10:00:00.000Z'),
      ], hasMore: false),
    ]));
    await n.load();

    n.applyUpdate(m('nope', 'x', '2026-08-18T10:00:00.000Z'));
    expect(n.state.messages.single.content, 'before');

    n.applyUpdate(m('m1', 'after', '2026-08-18T10:00:00.000Z'));
    expect(n.state.messages.single.content, 'after');
    expect(n.state.messages.length, 1);
  });
}
