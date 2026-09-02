import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/services/swipe_service.dart';
import 'package:flame/providers/match_provider.dart';
import 'package:flame/providers/user_provider.dart';
import 'package:flame/core/i18n/error_strings_for.dart';

final swipeServiceProvider = Provider<SwipeService>((ref) => SwipeService());

// Swipe actions provider
final swipeProvider = StateNotifierProvider<SwipeNotifier, SwipeState>((ref) {
  return SwipeNotifier(
    ref.watch(swipeServiceProvider),
    ref,
  );
});

class SwipeState {
  final bool isLoading;
  final Match? newMatch;
  final User? lastSwipedUser;
  final String? lastSwipeAction;
  final int? remainingSuperLikes;
  final String? error;
  final bool canUndo;

  const SwipeState({
    this.isLoading = false,
    this.newMatch,
    this.lastSwipedUser,
    this.lastSwipeAction,
    this.remainingSuperLikes,
    this.error,
    this.canUndo = false,
  });

  SwipeState copyWith({
    bool? isLoading,
    Match? newMatch,
    User? lastSwipedUser,
    String? lastSwipeAction,
    int? remainingSuperLikes,
    String? error,
    bool? canUndo,
  }) {
    return SwipeState(
      isLoading: isLoading ?? this.isLoading,
      newMatch: newMatch,
      lastSwipedUser: lastSwipedUser ?? this.lastSwipedUser,
      lastSwipeAction: lastSwipeAction ?? this.lastSwipeAction,
      remainingSuperLikes: remainingSuperLikes ?? this.remainingSuperLikes,
      error: error,
      canUndo: canUndo ?? this.canUndo,
    );
  }
}

/// Why an undo did or did not happen. A value rather than a message, because
/// this crosses from a provider into a widget that owns the localisation.
enum UndoOutcome { undone, nothingToUndo, premiumOnly, alreadyMessaged, failed }

class SwipeNotifier extends StateNotifier<SwipeState> {
  final SwipeService _swipeService;
  final Ref _ref;

  SwipeNotifier(this._swipeService, this._ref) : super(const SwipeState());

  // Swipe methods return null on success and an error message on failure.
  // The error string is what should be shown to the user — for 429 it's the
  // friendly "slow down" message set by ApiClient.
  Future<String?> like(User user) async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await _swipeService.likeUser(user.id);

    if (result.success && result.data != null) {
      final swipeResult = result.data!;


      if (swipeResult.isMatch && swipeResult.match != null) {
        // Add to matches
        _ref.read(matchesProvider.notifier).addMatch(swipeResult.match!);

        state = SwipeState(
          isLoading: false,
          newMatch: swipeResult.match,
          lastSwipedUser: user,
          lastSwipeAction: 'like',
          canUndo: _canUndo(),
        );
      } else {
        state = SwipeState(
          isLoading: false,
          lastSwipedUser: user,
          lastSwipeAction: 'like',
          canUndo: _canUndo(),
        );
      }
      return null;
    }

    final error = ErrorStringsFor.fromString(result.error);
    state = state.copyWith(isLoading: false, error: error);
    return error;
  }

  Future<String?> pass(User user) async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await _swipeService.passUser(user.id);

    if (result.success) {

      state = SwipeState(
        isLoading: false,
        lastSwipedUser: user,
        lastSwipeAction: 'pass',
        canUndo: _canUndo(),
      );
      return null;
    }

    final error = ErrorStringsFor.fromString(result.error);
    state = state.copyWith(isLoading: false, error: error);
    return error;
  }

  Future<String?> superLike(User user) async {
    // Check if user has remaining super likes
    if (state.remainingSuperLikes != null && state.remainingSuperLikes! <= 0) {
      const error = 'No super likes remaining today. Resets at midnight.';
      state = state.copyWith(error: error);
      return error;
    }

    state = state.copyWith(isLoading: true, error: null);

    final result = await _swipeService.superLikeUser(user.id);

    if (result.success && result.data != null) {
      final swipeResult = result.data!;


      if (swipeResult.isMatch && swipeResult.match != null) {
        // Add to matches
        _ref.read(matchesProvider.notifier).addMatch(swipeResult.match!);

        state = SwipeState(
          isLoading: false,
          newMatch: swipeResult.match,
          lastSwipedUser: user,
          lastSwipeAction: 'super_like',
          remainingSuperLikes: swipeResult.remainingSuperLikes,
          canUndo: _canUndo(),
        );
      } else {
        state = SwipeState(
          isLoading: false,
          lastSwipedUser: user,
          lastSwipeAction: 'super_like',
          remainingSuperLikes: swipeResult.remainingSuperLikes,
          canUndo: _canUndo(),
        );
      }
      return null;
    }

    // Check for specific error about super like limit
    final errorMessage = ErrorStringsFor.fromString(result.error);
    state = state.copyWith(
      isLoading: false,
      error: errorMessage,
    );
    return errorMessage;
  }

  bool _canUndo() {
    final userState = _ref.read(currentUserProvider);
    final user = userState.valueOrNull;

    if (user == null) return false;

    return user.isPremiumActive;
  }

  /// Takes back the last swipe, server-side.
  ///
  /// Returns an [UndoOutcome] rather than a bool: the three ways this can fail
  /// are different situations and the caller has to say which. The reasons are
  /// codes so they can be rendered in the reader's language — the two English
  /// sentences that used to live here could not be.
  ///
  /// The deck is NOT touched. It is append-only now, so the card is still in
  /// the list; putting it back would duplicate it. The caller steps the
  /// swiper's cursor back one instead.
  Future<UndoOutcome> undo() async {
    if (state.lastSwipedUser == null) return UndoOutcome.nothingToUndo;
    if (!_canUndo()) return UndoOutcome.premiumOnly;

    state = state.copyWith(isLoading: true, error: null);

    final result = await _swipeService.undoLastSwipe();
    final data = result.data;

    if (result.success && data != null && data.undone == true) {
      state = const SwipeState(isLoading: false);
      return UndoOutcome.undone;
    }

    state = state.copyWith(isLoading: false);
    return switch (data?.undoReason) {
      'ALREADY_MESSAGED' => UndoOutcome.alreadyMessaged,
      'NOTHING_TO_UNDO' => UndoOutcome.nothingToUndo,
      _ => UndoOutcome.failed,
    };
  }

  void clearNewMatch() {
    state = state.copyWith(newMatch: null);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Provider for showing match modal
final showMatchModalProvider = StateProvider<Match?>((ref) {
  return ref.watch(swipeProvider).newMatch;
});

// Provider for remaining super likes count
final remainingSuperLikesProvider = Provider<int?>((ref) {
  return ref.watch(swipeProvider).remainingSuperLikes;
});

// Provider for checking if undo is available
final canUndoProvider = Provider<bool>((ref) {
  return ref.watch(swipeProvider).canUndo;
});
