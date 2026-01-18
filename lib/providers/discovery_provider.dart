import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/services/discovery_service.dart';

final discoveryServiceProvider = Provider<DiscoveryService>((ref) => DiscoveryService());

// Discovery provider with async loading from API
final discoveryProvider = StateNotifierProvider<DiscoveryNotifier, AsyncValue<List<User>>>((ref) {
  return DiscoveryNotifier(ref.watch(discoveryServiceProvider));
});

class DiscoveryNotifier extends StateNotifier<AsyncValue<List<User>>> {
  final DiscoveryService _discoveryService;
  bool _hasMore = true;
  int _offset = 0;
  static const int _limit = 10;

  DiscoveryNotifier(this._discoveryService) : super(const AsyncValue.loading());

  bool get hasMore => _hasMore;

  Future<void> loadPotentialMatches({bool refresh = false}) async {
    if (refresh) {
      _offset = 0;
      _hasMore = true;
      state = const AsyncValue.loading();
    }

    final result = await _discoveryService.getPotentialMatches(
      limit: _limit,
      offset: _offset,
    );

    if (result.success && result.data != null) {
      final discoveryResult = result.data!;
      _hasMore = discoveryResult.hasMore;

      if (refresh || _offset == 0) {
        state = AsyncValue.data(discoveryResult.users);
      } else {
        final current = state.valueOrNull ?? [];
        state = AsyncValue.data([...current, ...discoveryResult.users]);
      }
      _offset += discoveryResult.users.length;
    } else {
      state = AsyncValue.error(result.error ?? 'Failed to load potential matches', StackTrace.current);
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;

    final result = await _discoveryService.getPotentialMatches(
      limit: _limit,
      offset: _offset,
    );

    if (result.success && result.data != null) {
      final discoveryResult = result.data!;
      _hasMore = discoveryResult.hasMore;
      final current = state.valueOrNull ?? [];
      state = AsyncValue.data([...current, ...discoveryResult.users]);
      _offset += discoveryResult.users.length;
    }
  }

  void removeUser(String userId) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.where((u) => u.id != userId).toList());
  }

  void undoRemove(User user) {
    final current = state.valueOrNull ?? [];
    // Add user back to the front
    state = AsyncValue.data([user, ...current]);
  }

  User? get currentUser {
    final users = state.valueOrNull ?? [];
    return users.isNotEmpty ? users.first : null;
  }
}

// Current card index for swipe stack
final currentCardIndexProvider = StateProvider<int>((ref) => 0);
