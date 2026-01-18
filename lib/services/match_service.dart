import 'package:flame/models/match.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/user_service.dart';

class MatchService {
  final ApiClient _apiClient = ApiClient();

  // Get all matches
  Future<ServiceResult<MatchesResult>> getMatches({
    int limit = 20,
    int offset = 0,
    bool newOnly = false,
  }) async {
    final response = await _apiClient.get(
      '/matches',
      queryParams: {
        'limit': limit.toString(),
        'offset': offset.toString(),
        'new_only': newOnly.toString(),
      },
    );

    if (response.success && response.data != null) {
      final matchesData = response.data['matches'] as List? ?? [];
      final matches = matchesData.map((m) => Match.fromJson(m)).toList();

      final pagination = response.data['pagination'] as Map<String, dynamic>? ?? {};

      return ServiceResult.success(MatchesResult(
        matches: matches,
        total: pagination['total'] ?? matches.length,
        limit: pagination['limit'] ?? limit,
        offset: pagination['offset'] ?? offset,
        hasMore: pagination['has_more'] ?? false,
      ));
    }

    return ServiceResult.failure(response.error ?? 'Failed to get matches');
  }

  // Unmatch user
  Future<ServiceResult<void>> unmatch(String matchId) async {
    final response = await _apiClient.delete('/matches/$matchId');

    if (response.success) {
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to unmatch');
  }

  // Mark match as seen (not new)
  Future<ServiceResult<Match>> markMatchAsSeen(String matchId) async {
    final response = await _apiClient.patch('/matches/$matchId', body: {
      'is_new': false,
    });

    if (response.success && response.data != null) {
      return ServiceResult.success(Match.fromJson(response.data));
    }

    return ServiceResult.failure(response.error ?? 'Failed to update match');
  }
}

class MatchesResult {
  final List<Match> matches;
  final int total;
  final int limit;
  final int offset;
  final bool hasMore;

  MatchesResult({
    required this.matches,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });
}
