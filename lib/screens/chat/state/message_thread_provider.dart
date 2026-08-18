import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/models/models.dart';
import 'package:flame/providers/chat_provider.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/screens/chat/chat_rows.dart';
import 'package:flame/services/chat_service.dart';

/// Everything one open conversation needs in order to render.
///
/// [rows] is derived from [messages] and carried here rather than computed in
/// `build()`. It used to be rebuilt on every rebuild — including on every
/// presence event, typing toggle and recording tick — and the old call passed
/// `DateTime.now()` inline, so the result could never be memoized.
class MessageThreadState {
  /// Oldest-first, which is display order. The server answers newest-first.
  final List<Message> messages;

  /// Separators and grouping for [messages]. Recomputed only when [messages]
  /// changes identity.
  final List<ChatRow> rows;

  /// Id of the oldest loaded message — the cursor for the next page. Anchors the
  /// *older* end of the loaded window, so a newer arrival never moves it.
  final String? oldestId;

  final bool hasMore;
  final bool isLoadingInitial;
  final bool isLoadingMore;

  /// Non-null when the last load failed.
  ///
  /// Kept distinct from "no messages" on purpose: a failed load used to leave
  /// the list empty, which rendered the say-hello prompt and invited the user to
  /// greet a thread that had not loaded.
  final String? error;

  const MessageThreadState({
    required this.messages,
    required this.rows,
    required this.oldestId,
    required this.hasMore,
    required this.isLoadingInitial,
    required this.isLoadingMore,
    required this.error,
  });

  factory MessageThreadState.loading() => const MessageThreadState(
        messages: [],
        rows: [],
        oldestId: null,
        hasMore: true,
        isLoadingInitial: true,
        isLoadingMore: false,
        error: null,
      );

  /// Loaded, no error, nothing in the thread. The only state that may show the
  /// "say hello" prompt.
  bool get isEmpty => !isLoadingInitial && error == null && messages.isEmpty;

  /// [messages] is the only field that invalidates [rows], so passing it
  /// recomputes them and omitting it reuses the existing list by identity.
  ///
  /// [error] cannot be cleared by passing null — null means "leave it alone",
  /// which is what every non-load mutation wants. Use [clearError].
  MessageThreadState copyWith({
    List<Message>? messages,
    String? oldestId,
    bool? hasMore,
    bool? isLoadingInitial,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
  }) {
    return MessageThreadState(
      messages: messages ?? this.messages,
      rows: messages == null ? rows : buildChatRows(messages),
      oldestId: oldestId ?? this.oldestId,
      hasMore: hasMore ?? this.hasMore,
      isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Owns one open conversation's messages.
///
/// Before this existed the thread lived in `_ChatScreenState._messages` while
/// `conversationsProvider` held a second copy, and the two were reconciled
/// inside `build()`.
class MessageThreadNotifier extends StateNotifier<MessageThreadState> {
  MessageThreadNotifier({
    required this.conversationId,
    required ChatService service,
    required RealtimeConnection connection,
  })  : _service = service,
        _connection = connection,
        super(MessageThreadState.loading());

  final String conversationId;
  final ChatService _service;
  final RealtimeConnection _connection;

  static const int pageSize = 30;

  /// Fetches the newest page, replacing whatever is loaded.
  ///
  /// Replaces rather than merges so a retry after a failure starts clean.
  Future<void> load() async {
    state = state.copyWith(isLoadingInitial: true, clearError: true);

    final result = await _service.getMessages(conversationId, limit: pageSize);
    if (!mounted) return;

    if (!result.success || result.data == null) {
      state = state.copyWith(isLoadingInitial: false, error: result.error);
      return;
    }

    final page = result.data!.messages.reversed.toList();
    state = state.copyWith(
      messages: page,
      oldestId: page.isEmpty ? null : page.first.id,
      hasMore: result.data!.hasMore,
      isLoadingInitial: false,
      clearError: true,
    );
  }

  Future<void> loadMore() async {
    // Filled in by the next task.
  }
}

final messageThreadProvider = StateNotifierProvider.autoDispose
    .family<MessageThreadNotifier, MessageThreadState, String>(
        (ref, conversationId) {
  final notifier = MessageThreadNotifier(
    conversationId: conversationId,
    service: ref.watch(chatServiceProvider),
    connection: ref.watch(realtimeConnectionProvider),
  );
  // autoDispose without keepAlive: leaving the chat drops the thread and its
  // socket subscription. Re-entering refetches, which is what the screen already
  // did, and memory stays bounded rather than accumulating one loaded thread per
  // conversation visited. An LRU cache is a later decision with its own evidence.
  ref.onDispose(notifier.dispose);
  return notifier;
});
