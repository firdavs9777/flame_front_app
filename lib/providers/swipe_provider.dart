import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/services/swipe_service.dart';
import 'package:flame/providers/discovery_provider.dart';
import 'package:flame/providers/match_provider.dart';
import 'package:flame/providers/user_provider.dart';

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

class SwipeNotifier extends StateNotifier<SwipeState> {
  final SwipeService _swipeService;
  final Ref _ref;

  SwipeNotifier(this._swipeService, this._ref) : super(const SwipeState());

  Future<bool> like(User user) async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await _swipeService.likeUser(user.id);

    if (result.success && result.data != null) {
      final swipeResult = result.data!;

      // Remove user from discovery
      _ref.read(discoveryProvider.notifier).removeUser(user.id);

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
      return true;
    }

    state = state.copyWith(
      isLoading: false,
      error: result.error ?? 'Failed to like user',
    );
    return false;
  }

  Future<bool> pass(User user) async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await _swipeService.passUser(user.id);

    if (result.success) {
      // Remove user from discovery
      _ref.read(discoveryProvider.notifier).removeUser(user.id);

      state = SwipeState(
        isLoading: false,
        lastSwipedUser: user,
        lastSwipeAction: 'pass',
        canUndo: _canUndo(),
      );
      return true;
    }

    state = state.copyWith(
      isLoading: false,
      error: result.error ?? 'Failed to pass user',
    );
    return false;
  }

  Future<bool> superLike(User user) async {
    // Check if user has remaining super likes
    if (state.remainingSuperLikes != null && state.remainingSuperLikes! <= 0) {
      state = state.copyWith(
        error: 'No super likes remaining today. Resets at midnight.',
      );
      return false;
    }

    state = state.copyWith(isLoading: true, error: null);

    final result = await _swipeService.superLikeUser(user.id);

    if (result.success && result.data != null) {
      final swipeResult = result.data!;

      // Remove user from discovery
      _ref.read(discoveryProvider.notifier).removeUser(user.id);

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
      return true;
    }

    // Check for specific error about super like limit
    final errorMessage = result.error ?? 'Failed to super like user';
    state = state.copyWith(
      isLoading: false,
      error: errorMessage,
    );
    return false;
  }

  bool _canUndo() {
    // Check if user is premium
    final userState = _ref.read(currentUserProvider);
    final user = userState.valueOrNull;

    if (user == null) return false;

    // Check if user is premium and premium hasn't expired
    if (!user.isPremium) return false;

    if (user.premiumExpiresAt != null) {
      if (user.premiumExpiresAt!.isBefore(DateTime.now())) {
        return false;
      }
    }

    return true;
  }

  Future<bool> undo() async {
    if (state.lastSwipedUser == null) {
      state = state.copyWith(error: 'Nothing to undo');
      return false;
    }

    // Check if user can undo (premium only)
    if (!_canUndo()) {
      state = state.copyWith(
        error: 'Undo is a premium feature. Upgrade to use it!',
      );
      return false;
    }

    state = state.copyWith(isLoading: true, error: null);

    final result = await _swipeService.undoLastSwipe();

    if (result.success && result.data != null) {
      final swipeResult = result.data!;

      if (swipeResult.undone == true && swipeResult.undoneUser != null) {
        // Add user back to discovery
        _ref.read(discoveryProvider.notifier).undoRemove(swipeResult.undoneUser!);

        state = const SwipeState(isLoading: false);
        return true;
      }
    }

    state = state.copyWith(
      isLoading: false,
      error: result.error ?? 'Failed to undo swipe',
    );
    return false;
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
