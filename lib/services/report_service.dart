import 'package:flame/services/api_client.dart';
import 'package:flame/services/user_service.dart';

class ReportService {
  final ApiClient _apiClient = ApiClient();

  // Report user
  /// Reports [userId]. Pass [messageId] to report one message rather than the
  /// person — a moderator can act on "harassment" far faster with the offending
  /// message attached than with an account id alone.
  Future<ServiceResult<void>> reportUser({
    required String userId,
    required ReportReason reason,
    String? details,
    String? messageId,
  }) async {
    final body = <String, dynamic>{
      'user_id': userId,
      'reason': reason.toApiString(),
    };
    if (details != null) body['details'] = details;
    if (messageId != null) body['message_id'] = messageId;

    final response = await _apiClient.post('/reports', body: body);

    if (response.success) {
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to report user');
  }

  // Block user
  Future<ServiceResult<void>> blockUser(String userId) async {
    final response = await _apiClient.post('/blocks', body: {
      'user_id': userId,
    });

    if (response.success) {
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to block user');
  }

  // Unblock user
  Future<ServiceResult<void>> unblockUser(String userId) async {
    final response = await _apiClient.delete('/blocks/$userId');

    if (response.success) {
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to unblock user');
  }

  // Get blocked users
  Future<ServiceResult<List<BlockedUser>>> getBlockedUsers() async {
    final response = await _apiClient.get('/blocks');

    if (response.success && response.data != null) {
      final blockedData = response.data['blocked_users'] as List? ?? [];
      final blockedUsers = blockedData
          .map((b) => BlockedUser.fromJson(b))
          .toList();
      return ServiceResult.success(blockedUsers);
    }

    return ServiceResult.failure(response.error ?? 'Failed to get blocked users');
  }
}

enum ReportReason {
  inappropriateContent,
  fakeProfile,
  harassment,
  spam,
  underage,
  other;

  String toApiString() {
    switch (this) {
      case ReportReason.inappropriateContent:
        return 'inappropriate_content';
      case ReportReason.fakeProfile:
        return 'fake_profile';
      case ReportReason.harassment:
        return 'harassment';
      case ReportReason.spam:
        return 'spam';
      case ReportReason.underage:
        return 'underage';
      case ReportReason.other:
        return 'other';
    }
  }

  // No displayName here on purpose: a service-layer enum has no BuildContext,
  // and an English getter is what kept this flow untranslated. The label comes
  // from reportReasonLabel() in widgets/report_block_menu.dart.
}

class BlockedUser {
  final String id;
  final String name;
  final DateTime blockedAt;

  BlockedUser({
    required this.id,
    required this.name,
    required this.blockedAt,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> json) {
    return BlockedUser(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      blockedAt: json['blocked_at'] != null
          ? DateTime.parse(json['blocked_at'])
          : DateTime.now(),
    );
  }
}
