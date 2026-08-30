import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/core/i18n/error_strings_for.dart';
import 'package:flame/models/models.dart';
import 'package:flame/services/discovery_service.dart';

final discoveryServiceProvider = Provider<DiscoveryService>((ref) => DiscoveryService());

// Filters live in user preferences and are applied by the backend.
final discoveryProvider =
    StateNotifierProvider<DiscoveryNotifier, AsyncValue<List<User>>>((ref) {
  return DiscoveryNotifier(ref.watch(discoveryServiceProvider));
});

/// The swipe deck.
///
/// There is no offset. The server excludes everyone already swiped, so the head
/// of the filtered set is always the next unseen page — which is why [refill]
/// dedupes rather than paging: the head necessarily re-includes anything already
/// fetched but not yet swiped.
class DiscoveryNotifier extends StateNotifier<AsyncValue<List<User>>> {
  DiscoveryNotifier(this._service) : super(const AsyncValue.loading());

  final DiscoveryService _service;

  static const int pageSize = 10;

  /// Refill when the deck gets this short. A buffer, not a guarantee: a user
  /// swiping faster than the round trip can still empty it, which renders as the
  /// loading state — one reason loading, empty and error must stay distinct.
  static const int refillThreshold = 3;

  bool _hasMore = true;
  bool _fetching = false;

  bool get hasMore => _hasMore;

  /// Fetches the head, replacing the deck. Used on first open and on retry.
  Future<void> load({bool refresh = false}) async {
    if (refresh) state = const AsyncValue.loading();
    _fetching = true;
    final result = await _service.getPotentialMatches(limit: pageSize);
    _fetching = false;

    if (!mounted) return;
    if (!result.success || result.data == null) {
      // Distinct from an empty deck on purpose: an error must never render as
      // "you have seen everyone".
      state = AsyncValue.error(
          ErrorStringsFor.fromString(result.error), StackTrace.current);
      return;
    }
    _hasMore = result.data!.hasMore;
    state = AsyncValue.data(result.data!.users);
  }

  /// Tops the deck up. Keeps what is already held on failure.
  Future<void> refill() async {
    if (_fetching || !_hasMore) return;
    _fetching = true;
    final result = await _service.getPotentialMatches(limit: pageSize);
    _fetching = false;

    if (!mounted) return;
    if (!result.success || result.data == null) return;

    _hasMore = result.data!.hasMore;
    final held = state.valueOrNull ?? const <User>[];
    final heldIds = held.map((u) => u.id).toSet();
    final fresh = result.data!.users.where((u) => !heldIds.contains(u.id));
    state = AsyncValue.data([...held, ...fresh]);
  }

  /// Applies changed filters. Cannot merge — the cards already held were chosen
  /// under the old predicate, so keeping them would show results the new filters
  /// exclude, which reads as the filter not working.
  Future<void> clearAndReload() async {
    state = const AsyncValue.data(<User>[]);
    _hasMore = true;
    await load(refresh: true);
  }

  /// Drops a card from the deck.
  ///
  /// NOT called when a card is swiped, and that is the whole point. CardSwiper
  /// owns its own cursor and only ever advances it; `didUpdateWidget` does not
  /// reset it when `cardsCount` changes. So removing the swiped card shifted
  /// every later card down one while the cursor moved up one, and the deck
  /// skipped every other profile — u1, u3, u5 were never shown to anyone and
  /// never swiped, and the cursor eventually ran past the end and rendered
  /// blank cards that no longer reached the server.
  ///
  /// The deck is therefore append-only for as long as one CardSwiper is
  /// walking it. Swiped cards stay in the list, behind the cursor, and the
  /// server excludes them from the next load anyway.
  void removeUser(String userId) {
    final current = state.valueOrNull ?? const <User>[];
    state = AsyncValue.data(current.where((u) => u.id != userId).toList());
  }

  void undoRemove(User user) {
    final current = state.valueOrNull ?? const <User>[];
    state = AsyncValue.data([user, ...current]);
  }

  User? get currentUser {
    final users = state.valueOrNull ?? const <User>[];
    return users.isEmpty ? null : users.first;
  }
}

// Current card index for the swipe stack.
final currentCardIndexProvider = StateProvider<int>((ref) => 0);
