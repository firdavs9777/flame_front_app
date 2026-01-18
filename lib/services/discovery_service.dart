import 'package:flame/models/user.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/user_service.dart';

class DiscoveryService {
  final ApiClient _apiClient = ApiClient();

  // Get potential matches for discovery
  Future<ServiceResult<DiscoveryResult>> getPotentialMatches({
    int limit = 10,
    int offset = 0,
    int? minAge,
    int? maxAge,
    double? maxDistance,
    Gender? genderPreference,
    List<String>? interests,
    bool? onlineOnly,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };

    // Add filter parameters if provided
    if (minAge != null) queryParams['min_age'] = minAge.toString();
    if (maxAge != null) queryParams['max_age'] = maxAge.toString();
    if (maxDistance != null) queryParams['max_distance'] = maxDistance.toString();
    if (genderPreference != null) queryParams['gender'] = genderPreference.toApiString();
    if (onlineOnly == true) queryParams['online_only'] = 'true';
    if (interests != null && interests.isNotEmpty) {
      queryParams['interests'] = interests.join(',');
    }

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
