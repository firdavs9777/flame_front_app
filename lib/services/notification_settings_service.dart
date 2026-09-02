import 'package:flame/models/notification_settings.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

class NotificationSettingsService {
  final ApiClient _apiClient;

  NotificationSettingsService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  Future<ServiceResult<NotificationSettings>> getSettings() async {
    final response = await _apiClient.get('/notifications/settings');

    if (response.success && response.data != null) {
      return ServiceResult.success(
        NotificationSettings.fromJson(response.data),
      );
    }

    return ServiceResult.failure(
      response.error ?? 'Failed to load notification settings',
    );
  }

  Future<ServiceResult<NotificationSettings>> updateSettings({
    bool? enabled,
    bool? chatMessages,
    bool? matches,
    bool? promotions,
    bool? reengagement,
    bool? promotionsPush,
    bool? reengagementPush,
  }) async {
    final body = NotificationSettings.toPutBody(
      enabled: enabled,
      chatMessages: chatMessages,
      matches: matches,
      promotions: promotions,
      reengagement: reengagement,
      promotionsPush: promotionsPush,
      reengagementPush: reengagementPush,
    );

    final response = await _apiClient.put(
      '/notifications/settings',
      body: body,
    );

    if (response.success && response.data != null) {
      return ServiceResult.success(
        NotificationSettings.fromJson(response.data),
      );
    }

    return ServiceResult.failure(
      response.error ?? 'Failed to update notification settings',
    );
  }
}
