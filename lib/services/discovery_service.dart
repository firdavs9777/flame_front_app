import 'package:flame/models/user.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/user_service.dart';

class DiscoveryService {
  final ApiClient _apiClient = ApiClient();

  // Get potential matches for discovery
  // Note: Filters (min_age, max_age, max_distance) are stored in user preferences
  // and automatically applied by the backend
  Future<ServiceResult<DiscoveryResult>> getPotentialMatches({
    int limit = 10,
    int offset = 0,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };

    final response = await _apiClient.get(
      '/discover',
      queryParams: queryParams,
    );

    if (response.success && response.data != null) {
      final usersData = response.data['users'] as List? ?? [];
      final users = usersData.map((u) => User.fromJson(u)).toList();

      final pagination = response.data['pagination'] as Map<String, dynamic>? ?? {};

      return ServiceResult.success(DiscoveryResult(
        users: users,
        total: pagination['total'] ?? users.length,
        limit: pagination['limit'] ?? limit,
        offset: pagination['offset'] ?? offset,
        hasMore: pagination['has_more'] ?? false,
      ));
    }

    return ServiceResult.failure(response.error ?? 'Failed to get potential matches');
  }
}

class DiscoveryResult {
  final List<User> users;
  final int total;
  final int limit;
  final int offset;
  final bool hasMore;

  DiscoveryResult({
    required this.users,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });
}
