import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'constants.dart';
import 'outbox.dart';
import 'outbox_entry.dart';
import 'socket_client.dart';
import 'socket_state.dart';

final socketClientProvider = Provider<SocketClient>((ref) {
  final c = SocketClient();
  ref.onDispose(c.dispose);
  return c;
});

final socketStateProvider = StreamProvider<SocketState>((ref) {
  return ref.watch(socketClientProvider).stateStream;
});

final outboxRepoProvider = Provider<OutboxRepo>((ref) {
  final r = OutboxRepo();
  return r;
});

final outboxProvider = StateNotifierProvider<OutboxNotifier, List<OutboxEntry>>((ref) {
  return OutboxNotifier(ref);
});

class OutboxNotifier extends StateNotifier<List<OutboxEntry>> {
  final Ref ref;
  OutboxNotifier(this.ref) : super([]) {
    _init();
  }

  Future<void> _init() async {
    final repo = ref.read(outboxRepoProvider);
    await repo.load();
    await repo.resetSendingToPending();
    state = repo.all;
  }

  Future<void> sendText({
    required String conversationId,
    required String content,
    String? replyToMessageId,
  }) async {
    final repo = ref.read(outboxRepoProvider);
    final entry = OutboxEntry(
      clientMessageId: const Uuid().v4(),
      conversationId: conversationId,
      type: 'text',
      content: content,
      replyToMessageId: replyToMessageId,
      createdAt: DateTime.now(),
    );
    await repo.enqueue(entry);
    state = repo.all;
    await _flushOne(entry);
  }

  Future<void> retry(String cmid) async {
    final repo = ref.read(outboxRepoProvider);
    final e = repo.all.firstWhere((x) => x.clientMessageId == cmid);
    state = repo.all;
    await _flushOne(e);
  }

  Future<void> flushAll() async {
    final repo = ref.read(outboxRepoProvider);
    for (final e in repo.all.where((e) => e.status != OutboxStatus.failed)) {
      await _flushOne(e);
    }
  }

  Future<void> _flushOne(OutboxEntry e) async {
    final repo = ref.read(outboxRepoProvider);
    final socket = ref.read(socketClientProvider);
    if (socket.state.status != SocketStatus.connected) return;
    await repo.markSending(e.clientMessageId);
    state = repo.all;
    try {
      final resp = await socket.emitWithAckTimeout(
        RtEvents.messageSend,
        {
          'client_message_id': e.clientMessageId,
          'conversation_id': e.conversationId,
          'type': e.type,
          'content': e.content,
          if (e.media != null) 'media': e.media,
          if (e.replyToMessageId != null) 'reply_to_message_id': e.replyToMessageId,
        },
        timeout: RtTimeouts.ackTimeout,
      );
      if (resp is Map && resp['ok'] == true) {
        await repo.markSent(
          e.clientMessageId,
          canonicalMessageId: resp['message']['id'],
        );
      } else if (resp is Map) {
        final code = (resp['error'] ?? const {})['code'] ?? 'UNKNOWN';
        if (code == 'TRANSIENT') {
          await repo.bumpAttempt(e.clientMessageId, errorCode: code);
        } else {
          await repo.markFailedTerminal(e.clientMessageId, errorCode: code);
        }
      } else {
        await repo.bumpAttempt(e.clientMessageId, errorCode: 'BAD_ACK');
      }
    } on TimeoutException {
      await repo.bumpAttempt(e.clientMessageId, errorCode: 'TIMEOUT');
    } catch (err) {
      await repo.bumpAttempt(e.clientMessageId, errorCode: 'NET');
    }
    state = repo.all;
  }
}
