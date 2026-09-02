import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Caps how many AUTOMATIC (default-on) translations run at once.
///
/// `/translate` is a metered, rate-limited endpoint. Opening one
/// mismatched-language thread can otherwise fire a dozen-plus simultaneous
/// requests as bubbles settle into view, and the tail of that burst gets
/// 429s — the feature half-works, silently, only for the messages unlucky
/// enough to be near the bottom of the burst.
///
/// This gate exists ONLY for that auto-trigger path, in
/// `message_bubble.dart`'s `_TranslateSectionState`. A manual tap must never
/// queue behind it — `TranslationNotifier.toggle`
/// (lib/providers/translation_provider.dart) is untouched and still fires
/// immediately, which is exactly why this cap lives here rather than inside
/// the shared service or provider.
class AutoTranslateGate {
  AutoTranslateGate({this.maxConcurrent = 3});

  final int maxConcurrent;
  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  /// Resolves once a slot is free — immediately if under the cap, otherwise
  /// once an earlier holder [release]s. Always pair with [release]: a leaked
  /// slot never opens again for the lifetime of this gate.
  Future<void> acquire() {
    if (_active < maxConcurrent) {
      _active++;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  /// Frees the caller's slot. If another attempt is queued, the slot is
  /// handed straight to it rather than the count dropping to be re-acquired
  /// later — the cap stays saturated across a burst instead of draining to
  /// idle between each completion.
  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return; // The slot transferred; `_active` is unchanged.
    }
    _active--;
  }
}

/// Waits [delay], then — unless [cancel] has been called — waits for a slot
/// on an [AutoTranslateGate] before running the scheduled work.
///
/// A plain Dart class with no Flutter dependency, so both halves of the
/// mechanism (the delay, and the cap) are testable with `fake_async` outside
/// a widget tree — the same way `ThreadPresenceNotifier`'s safety timer is
/// (see test/screens/chat/thread_presence_test.dart). A `State`'s own Timer
/// cannot be driven with `async.elapse`.
class AutoTranslateScheduler {
  AutoTranslateScheduler({this.delay = const Duration(milliseconds: 300)});

  final Duration delay;
  Timer? _timer;
  bool _cancelled = false;

  /// Starts the delay. [fire] runs after [delay] elapses AND a slot on
  /// [gate] is free — unless [cancel] is called first, at either point, in
  /// which case [fire] never runs and (if cancelled before a slot was ever
  /// requested) the gate is never touched at all.
  ///
  /// The bubbles that mount only transiently — while a thread's opening
  /// `jumpTo` forces a non-reversed list to build every item to compute
  /// total extent — unmount well inside [delay]. Cancelling them there is
  /// what keeps them from ever reaching the network.
  void start({
    required AutoTranslateGate gate,
    required Future<void> Function() fire,
  }) {
    _timer = Timer(delay, () async {
      if (_cancelled) return;
      await gate.acquire();
      try {
        if (_cancelled) return;
        await fire();
      } finally {
        gate.release();
      }
    });
  }

  /// Stops this attempt. Safe to call before [start], after [start] has
  /// already fired, or more than once — a bubble's `dispose()` calls this
  /// unconditionally.
  void cancel() {
    _cancelled = true;
    _timer?.cancel();
  }
}

/// One gate for the whole app: `MessageBubble`s come and go as a thread
/// scrolls, but the cap bounds total concurrent `/translate` calls, not
/// calls per bubble.
final autoTranslateGateProvider = Provider<AutoTranslateGate>((ref) {
  return AutoTranslateGate();
});
