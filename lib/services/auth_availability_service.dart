import 'package:flame/services/api_client.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

/// Checks whether auth identifiers (currently email) are available for
/// registration. Backed by the backend's `/auth/check-email` endpoint, which
/// returns `{success: true, data: {available: bool}}`.
class AuthAvailabilityService {
  final ApiClient _apiClient;

  AuthAvailabilityService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// Returns whether [email] is available (not already registered).
  Future<ServiceResult<bool>> checkEmail(String email) async {
    final response = await _apiClient.post('/auth/check-email', body: {'email': email});
    if (response.success && response.data != null) {
      return ServiceResult.success(response.data['available'] == true);
    }
    return ServiceResult.failure(response.error ?? 'Could not check email');
  }
}
