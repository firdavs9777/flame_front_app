import 'package:flame/services/api_client.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

/// Device-token registration, backed by `/notifications/register-token` and
/// `/notifications/remove-token/:deviceId`.
///
/// The request body is camelCase (`deviceId`), unlike most GET responses in
/// this API, because the route validates with a zod schema that names it that
/// way. `platform` is a strict enum of exactly `ios` | `android`; anything else
/// is a 422, which is why [PushPlatform] exists rather than a bare string at
/// the call site.
class DeviceService {
  final ApiClient _apiClient;

  DeviceService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// Registers (or replaces) this device's FCM token.
  ///
  /// The backend upserts by [deviceId], so calling this repeatedly with the
  /// same device and a rotated token replaces the entry instead of adding one.
  Future<ServiceResult<bool>> registerToken({
    required String token,
    required String platform,
    required String deviceId,
  }) async {
    final response = await _apiClient.post(
      '/notifications/register-token',
      body: {
        'token': token,
        'platform': platform,
        'deviceId': deviceId,
      },
    );

    if (response.success) return ServiceResult.success(true);

    return ServiceResult.failure(
      response.error ?? 'Failed to register device token',
    );
  }

  /// Removes this device's token so a signed-out phone stops receiving pushes
  /// for the account that just left it.
  Future<ServiceResult<bool>> removeToken(String deviceId) async {
    final response = await _apiClient.delete(
      '/notifications/remove-token/$deviceId',
    );

    if (response.success) return ServiceResult.success(true);

    return ServiceResult.failure(
      response.error ?? 'Failed to remove device token',
    );
  }
}

/// The two values the backend's zod enum accepts.
abstract final class PushPlatform {
  static const android = 'android';
  static const ios = 'ios';
}
