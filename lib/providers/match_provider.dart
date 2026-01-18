import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/match_service.dart';

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
      state = AsyncValue.error(result.error ?? 'Failed to load matches', StackTrace.current);
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

  Future<bool> markAsSeen(String matchId) async {
    final result = await _matchService.markMatchAsSeen(matchId);

    if (result.success) {
      final currentMatches = state.valueOrNull ?? [];
      state = AsyncValue.data(currentMatches.map((match) {
        if (match.id == matchId) {
          return match.copyWith(isNew: false);
        }
        return match;
      }).toList());
      return true;
    }
    return false;
  }

  Future<bool> unmatch(String matchId) async {
    final result = await _matchService.unmatch(matchId);

    if (result.success) {
      final currentMatches = state.valueOrNull ?? [];
      state = AsyncValue.data(
        currentMatches.where((m) => m.id != matchId).toList(),
      );
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
