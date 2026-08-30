import 'package:flame/models/match.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/user_service.dart';

class MatchService {
  final ApiClient _apiClient = ApiClient();

  // Get all matches
  Future<ServiceResult<MatchesResult>> getMatches({
    int limit = 20,
    int offset = 0,
  }) async {
    // No `new_only`: no route has ever read it, and the listing reports
    // is_new: false for everything by design — only a swipe response knows a
    // match is new. Sending it looked like a filter that worked.
    final response = await _apiClient.get(
      '/matches',
      queryParams: {
        'limit': limit.toString(),
        'offset': offset.toString(),
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
