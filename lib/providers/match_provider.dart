import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/services/match_service.dart';
import 'package:flame/core/i18n/error_strings_for.dart';

final matchServiceProvider = Provider<MatchService>((ref) => MatchService());

// Matches provider with async loading from API
final matchesProvider = StateNotifierProvider<MatchesNotifier, AsyncValue<List<Match>>>((ref) {
  return MatchesNotifier(ref.watch(matchServiceProvider));
});

class MatchesNotifier extends StateNotifier<AsyncValue<List<Match>>> {
  final MatchService _matchService;
  bool _hasMore = true;
  int _offset = 0;
  static const int _limit = 20;

  MatchesNotifier(this._matchService) : super(const AsyncValue.loading());

  bool get hasMore => _hasMore;

  Future<void> loadMatches({bool refresh = false}) async {
    if (refresh) {
      _offset = 0;
      _hasMore = true;
      state = const AsyncValue.loading();
    }

    final result = await _matchService.getMatches(
      limit: _limit,
      offset: _offset,
    );

    if (result.success && result.data != null) {
      final matchesResult = result.data!;
      _hasMore = matchesResult.hasMore;

      if (refresh || _offset == 0) {
        state = AsyncValue.data(matchesResult.matches);
      } else {
        final currentMatches = state.valueOrNull ?? [];
        state = AsyncValue.data([...currentMatches, ...matchesResult.matches]);
      }
      _offset += matchesResult.matches.length;
    } else {
      state = AsyncValue.error(ErrorStringsFor.fromString(result.error), StackTrace.current);
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    await loadMatches();
  }

  void addMatch(Match match) {
    final currentMatches = state.valueOrNull ?? [];
    state = AsyncValue.data([match, ...currentMatches]);
  }


  /// Removes a match locally. Call after the server confirms the unmatch so the
  /// list does not flicker back on a failed request.
  void removeMatch(String matchId) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(current.where((m) => m.id != matchId).toList());
  }

  Future<bool> unmatch(String matchId) async {
    final result = await _matchService.unmatch(matchId);

    if (result.success) {
      removeMatch(matchId);
      return true;
    }
    return false;
  }
}

final newMatchesCountProvider = Provider<int>((ref) {
  final matchesState = ref.watch(matchesProvider);
  return matchesState.maybeWhen(
    data: (matches) => matches.where((m) => m.isNew).length,
    orElse: () => 0,
  );
});
