import 'package:flame/models/user.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/user_service.dart';

class DiscoveryService {
  DiscoveryService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  /// The next unseen profiles.
  ///
  /// Sends no offset. The server excludes everyone already swiped, so the head of
  /// the filtered set IS the next page — and paging it with an offset made the
  /// deck step over profiles as that excluded set grew. Filters live in user
  /// preferences and are applied server-side.
  Future<ServiceResult<DiscoveryResult>> getPotentialMatches({int limit = 10}) async {
    final response = await _apiClient.get(
      '/discover',
      queryParams: {'limit': limit.toString()},
    );

    if (response.success && response.data != null) {
      final usersData = response.data['users'] as List? ?? [];
      final pagination = response.data['pagination'] as Map<String, dynamic>? ?? {};

      return ServiceResult.success(DiscoveryResult(
        users: usersData.map((u) => User.fromJson(u)).toList(),
        hasMore: pagination['has_more'] ?? false,
      ));
    }

    return ServiceResult.failure(response.error ?? 'Failed to get potential matches');
  }
}

/// `total` and `offset` are deliberately absent: both existed only to serve
/// offset paging, the head path does not compute them, and keeping them as
/// `?? users.length` fallbacks would let a caller read a plausible-looking number
/// that means nothing.
class DiscoveryResult {
  const DiscoveryResult({required this.users, required this.hasMore});

  final List<User> users;
  final bool hasMore;
}
