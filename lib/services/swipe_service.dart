import '../models/user.dart';
import '../models/match.dart';
import 'api_client.dart';
import 'user_service.dart';

class SwipeService {
  final ApiClient _apiClient = ApiClient();

  // Like user (swipe right)
  Future<ServiceResult<SwipeResult>> likeUser(String userId) async {
    final response = await _apiClient.post('/swipes/like', body: {
      'user_id': userId,
    });

    if (response.success && response.data != null) {
      final isMatch = response.data['is_match'] ?? false;
      Match? match;

      if (isMatch && response.data['match'] != null) {
        match = Match.fromJson(response.data['match']);
      }

      return ServiceResult.success(SwipeResult(
        liked: response.data['liked'] ?? true,
        isMatch: isMatch,
        match: match,
      ));
    }

    return ServiceResult.failure(response.error ?? 'Failed to like user');
  }

  // Pass user (swipe left)
  Future<ServiceResult<SwipeResult>> passUser(String userId) async {
    final response = await _apiClient.post('/swipes/pass', body: {
      'user_id': userId,
    });

    if (response.success && response.data != null) {
      return ServiceResult.success(SwipeResult(
        passed: response.data['passed'] ?? true,
      ));
    }

    return ServiceResult.failure(response.error ?? 'Failed to pass user');
  }

  // Super like user
  Future<ServiceResult<SwipeResult>> superLikeUser(String userId) async {
    final response = await _apiClient.post('/swipes/super-like', body: {
      'user_id': userId,
    });

    if (response.success && response.data != null) {
      final isMatch = response.data['is_match'] ?? false;
      Match? match;

      if (isMatch && response.data['match'] != null) {
        match = Match.fromJson(response.data['match']);
      }

      return ServiceResult.success(SwipeResult(
        superLiked: response.data['super_liked'] ?? true,
        isMatch: isMatch,
        match: match,
        remainingSuperLikes: response.data['remaining_super_likes'],
      ));
    }

    return ServiceResult.failure(response.error ?? 'Failed to super like user');
  }

  // Undo last swipe
  Future<ServiceResult<SwipeResult>> undoLastSwipe() async {
    final response = await _apiClient.post('/swipes/undo');

    if (response.success && response.data != null) {
      User? user;
      if (response.data['user'] != null) {
        user = User.fromJson(response.data['user']);
      }

      return ServiceResult.success(SwipeResult(
        undone: response.data['undone'] ?? true,
        undoneUser: user,
      ));
    }

    return ServiceResult.failure(response.error ?? 'Failed to undo swipe');
  }
}

class SwipeResult {
  final bool? liked;
  final bool? passed;
  final bool? superLiked;
  final bool? undone;
  final bool isMatch;
  final Match? match;
  final int? remainingSuperLikes;
  final User? undoneUser;

  SwipeResult({
    this.liked,
    this.passed,
    this.superLiked,
    this.undone,
    this.isMatch = false,
    this.match,
    this.remainingSuperLikes,
    this.undoneUser,
  });
}
