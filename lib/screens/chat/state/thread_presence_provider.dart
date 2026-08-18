import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/providers/realtime_provider.dart';

/// Whether the partner is typing, and whether they are online.
class ThreadPresenceState {
  final bool isOtherTyping;
  final bool isOtherOnline;

  const ThreadPresenceState({
    required this.isOtherTyping,
    required this.isOtherOnline,
  });

  ThreadPresenceState copyWith({bool? isOtherTyping, bool? isOtherOnline}) =>
      ThreadPresenceState(
        isOtherTyping: isOtherTyping ?? this.isOtherTyping,
        isOtherOnline: isOtherOnline ?? this.isOtherOnline,
      );
}

/// Family key. Value-equal so the same open thread resolves to one notifier
/// rather than a fresh one on every rebuild.
class ThreadPresenceArgs {
  final String conversationId;
  final String otherUserId;

  /// The REST snapshot of the partner's online state, so the dot has a real
  /// value before any socket event arrives rather than a synthesized "offline".
  final bool seedOnline;

  const ThreadPresenceArgs({
    required this.conversationId,
    required this.otherUserId,
    required this.seedOnline,
  });

  @override
  bool operator ==(Object other) =>
      other is ThreadPresenceArgs &&
      other.conversationId == conversationId &&
      other.otherUserId == otherUserId &&
      other.seedOnline == seedOnline;

  @override
  int get hashCode => Object.hash(conversationId, otherUserId, seedOnline);
}

/// Ephemeral, per-open-thread typing and presence.
///
/// Deliberately separate from `conversationsProvider.applyPresence`, which serves
/// the conversation list's online dots and has to keep working while no thread is
/// open. Both subscribe to the same streams; presence is idempotent per user id,
/// so two subscribers cannot disagree.
///
/// This exists so the screen stops owning two timers, `_isTyping`,
/// `_isOtherUserTypingFlame` and a presence map.
class ThreadPresenceNotifier extends StateNotifier<ThreadPresenceState> {
  ThreadPresenceNotifier({
    required this.conversationId,
    required this.otherUserId,
    required bool seedOnline,
    required RealtimeConnection connection,
  })  : _connection = connection,
        super(ThreadPresenceState(
          isOtherTyping: false,
          isOtherOnline: seedOnline,
        ));

  final String conversationId;
  final String otherUserId;
  final RealtimeConnection _connection;

  final List<StreamSubscription<void>> _subs = [];

  /// Hides the incoming indicator if a `stopTyping` is dropped, which would
  /// otherwise strand it on for the life of the screen.
  Timer? _incomingSafety;

  /// Ends our own typing run after a pause, so we emit once per run rather than
  /// once per keystroke.
  Timer? _outgoingIdle;
  bool _emittingTyping = false;

  static const incomingTimeout = Duration(seconds: 5);
  static const outgoingIdleGap = Duration(seconds: 3);

  void listen() {
    if (_subs.isNotEmpty) return;
    _subs.addAll([
      _connection.typing.listen((e) {
        if (e.conversationId != conversationId || !mounted) return;
        state = state.copyWith(isOtherTyping: true);
        _incomingSafety?.cancel();
        _incomingSafety = Timer(incomingTimeout, () {
          if (mounted) state = state.copyWith(isOtherTyping: false);
        });
      }),
      _connection.stopTyping.listen((e) {
        if (e.conversationId != conversationId || !mounted) return;
        _incomingSafety?.cancel();
        state = state.copyWith(isOtherTyping: false);
      }),
      _connection.presence.listen((e) {
        if (e.userId != otherUserId || !mounted) return;
        state = state.copyWith(isOtherOnline: e.online);
      }),
      _connection.presenceBulk.listen((ids) {
        if (!mounted) return;
        state = state.copyWith(isOtherOnline: ids.contains(otherUserId));
      }),
    ]);
  }

  /// Call on every composer keystroke. Emits `typing` on the false→true edge
  /// only, and schedules a `stopTyping` for after the pause.
  void onOutgoingText(String text) {
    final socket = _connection.socket;
    if (socket == null || !socket.isConnected) return;

    if (text.isEmpty) {
      stopTypingNow();
      return;
    }

    if (!_emittingTyping) {
      _emittingTyping = true;
      socket.emitTyping(otherUserId, conversationId);
    }

    _outgoingIdle?.cancel();
    _outgoingIdle = Timer(outgoingIdleGap, stopTypingNow);
  }

  /// Emits `stopTyping` if we were mid-run. Called on idle, on send, and on
  /// dispose — leaving a run open would strand the indicator on the partner's
  /// screen until their own safety timer fired.
  void stopTypingNow() {
    _outgoingIdle?.cancel();
    _outgoingIdle = null;
    if (!_emittingTyping) return;
    _emittingTyping = false;

    final socket = _connection.socket;
    if (socket != null && socket.isConnected) {
      socket.emitStopTyping(otherUserId, conversationId);
    }
  }

  @override
  void dispose() {
    _incomingSafety?.cancel();
    stopTypingNow();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    super.dispose();
  }
}

final threadPresenceProvider = StateNotifierProvider.autoDispose
    .family<ThreadPresenceNotifier, ThreadPresenceState, ThreadPresenceArgs>(
        (ref, args) {
  final notifier = ThreadPresenceNotifier(
    conversationId: args.conversationId,
    otherUserId: args.otherUserId,
    seedOnline: args.seedOnline,
    connection: ref.watch(realtimeConnectionProvider),
  )..listen();
  ref.onDispose(notifier.dispose);
  return notifier;
});
