import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/services/discovery_service.dart';
import 'package:flame/providers/filter_provider.dart';

final discoveryServiceProvider = Provider<DiscoveryService>((ref) => DiscoveryService());

// Discovery provider with async loading from API
final discoveryProvider = StateNotifierProvider<DiscoveryNotifier, AsyncValue<List<User>>>((ref) {
  return DiscoveryNotifier(ref.watch(discoveryServiceProvider), ref);
});

class DiscoveryNotifier extends StateNotifier<AsyncValue<List<User>>> {
  final DiscoveryService _discoveryService;
  final Ref _ref;
  bool _hasMore = true;
  int _offset = 0;
  static const int _limit = 10;

  // Store current filters for loadMore
  DiscoveryFilters? _currentFilters;

  DiscoveryNotifier(this._discoveryService, this._ref) : super(const AsyncValue.loading());

  bool get hasMore => _hasMore;

  Future<void> loadPotentialMatches({bool refresh = false, DiscoveryFilters? filters}) async {
    if (refresh) {
      _offset = 0;
      _hasMore = true;
      state = const AsyncValue.loading();
    }

    // Use provided filters or read from provider
    final DiscoveryFilters currentFilters = filters ?? _ref.read(filterProvider);
    _currentFilters = currentFilters;

    final result = await _discoveryService.getPotentialMatches(
      limit: _limit,
      offset: _offset,
      minAge: currentFilters.minAge,
      maxAge: currentFilters.maxAge,
      maxDistance: currentFilters.maxDistance,
      genderPreference: currentFilters.genderPreference,
      interests: currentFilters.interests.isNotEmpty ? currentFilters.interests : null,
      onlineOnly: currentFilters.onlineOnly,
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

    // Use stored filters or read from provider
    final DiscoveryFilters filters = _currentFilters ?? _ref.read(filterProvider);

    final result = await _discoveryService.getPotentialMatches(
      limit: _limit,
      offset: _offset,
      minAge: filters.minAge,
      maxAge: filters.maxAge,
      maxDistance: filters.maxDistance,
      genderPreference: filters.genderPreference,
      interests: filters.interests.isNotEmpty ? filters.interests : null,
      onlineOnly: filters.onlineOnly,
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
