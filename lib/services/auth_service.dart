import 'package:flame/models/user.dart';
import 'package:flame/services/api_client.dart';

class AuthService {
  final ApiClient _apiClient = ApiClient();

  // Initialize service
  Future<void> init() async {
    await _apiClient.init();
  }

  // Check if user is logged in
  bool get isLoggedIn => _apiClient.hasTokens;

  // Login
  Future<AuthResult> login({
    required String email,
    required String password,
    String? deviceToken,
  }) async {
    final body = {
      'email': email,
      'password': password,
    };
    if (deviceToken != null) {
      body['device_token'] = deviceToken;
    }

    final response = await _apiClient.post('/auth/login', body: body);

    if (response.success && response.data != null) {
      final data = response.data;
      final tokens = data['tokens'];
      final userData = data['user'];

      // Save tokens
      await _apiClient.saveTokens(
        accessToken: tokens['access_token'],
        refreshToken: tokens['refresh_token'],
        userId: userData['id'],
      );

      // Parse user
      final user = User.fromJson(userData);

      return AuthResult(success: true, user: user);
    }

    return AuthResult(
      success: false,
      error: response.error ?? 'Login failed',
      errorCode: response.errorCode,
    );
  }

  // Register
  Future<AuthResult> register({
    required String email,
    required String password,
    required String name,
    required int age,
    required Gender gender,
    required Gender lookingFor,
    required String bio,
    required List<String> interests,
    required List<String> photos,
  }) async {
    final response = await _apiClient.post('/auth/register', body: {
      'email': email,
      'password': password,
      'name': name,
      'age': age,
      'gender': gender.toApiString(),
      'looking_for': lookingFor.toApiString(),
      'bio': bio,
      'interests': interests,
      'photos': photos,
    });

    if (response.success && response.data != null) {
      final data = response.data;
      final tokens = data['tokens'];
      final userData = data['user'];

      // Save tokens
      await _apiClient.saveTokens(
        accessToken: tokens['access_token'],
        refreshToken: tokens['refresh_token'],
        userId: userData['id'],
      );

      // Parse user
      final user = User.fromJson(userData);

      return AuthResult(success: true, user: user);
    }

    return AuthResult(
      success: false,
      error: response.error ?? 'Registration failed',
      errorCode: response.errorCode,
    );
  }

  // Verify Email
  Future<AuthResult> verifyEmail({
    required String email,
    required String code,
  }) async {
    final response = await _apiClient.post('/auth/verify-email', body: {
      'email': email,
      'code': code,
    });

    return AuthResult(
      success: response.success,
      message: response.message,
      error: response.error,
      errorCode: response.errorCode,
    );
  }

  // Resend Verification Code
  Future<AuthResult> resendVerificationCode() async {
    final response = await _apiClient.post('/auth/resend-verification');

    return AuthResult(
      success: response.success,
      message: response.message,
      error: response.error,
      errorCode: response.errorCode,
    );
  }

  // Logout
  Future<void> logout() async {
    await _apiClient.post('/auth/logout');
    await _apiClient.clearTokens();
  }

  // Get current user
  Future<AuthResult> getCurrentUser() async {
    final response = await _apiClient.get('/users/me');

    if (response.success && response.data != null) {
      final user = User.fromJson(response.data);
      return AuthResult(success: true, user: user);
    }

    return AuthResult(
      success: false,
      error: response.error ?? 'Failed to get user',
      errorCode: response.errorCode,
    );
  }

  // Forgot password
  Future<AuthResult> forgotPassword(String email) async {
    final response = await _apiClient.post('/auth/forgot-password', body: {
      'email': email,
    });

    return AuthResult(
      success: response.success,
      message: response.message,
      error: response.error,
      errorCode: response.errorCode,
    );
  }

  // Reset password with token (from email link)
  Future<AuthResult> resetPassword({
    required String token,
    required String password,
  }) async {
    final response = await _apiClient.post('/auth/reset-password', body: {
      'token': token,
      'password': password,
      'password_confirmation': password,
    });

    return AuthResult(
      success: response.success,
      message: response.message,
      error: response.error,
      errorCode: response.errorCode,
    );
  }

  // Change password
  Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _apiClient.post('/auth/change-password', body: {
      'current_password': currentPassword,
      'new_password': newPassword,
      'new_password_confirmation': newPassword,
    });

    return AuthResult(
      success: response.success,
      message: response.message,
      error: response.error,
      errorCode: response.errorCode,
    );
  }

  // Google Sign In
  Future<AuthResult> googleSignIn({
    required String idToken,
    String? deviceToken,
  }) async {
    final body = <String, dynamic>{
      'id_token': idToken,
    };
    if (deviceToken != null) {
      body['device_token'] = deviceToken;
    }

    final response = await _apiClient.post('/auth/google', body: body);

    if (response.success && response.data != null) {
      final data = response.data;
      final tokens = data['tokens'];
      final userData = data['user'];

      await _apiClient.saveTokens(
        accessToken: tokens['access_token'],
        refreshToken: tokens['refresh_token'],
        userId: userData['id'],
      );

      final user = User.fromJson(userData);
      return AuthResult(success: true, user: user);
    }

    return AuthResult(
      success: false,
      error: response.error ?? 'Google sign in failed',
      errorCode: response.errorCode,
    );
  }

  // Apple Sign In
  Future<AuthResult> appleSignIn({
    required String idToken,
    required String authorizationCode,
    String? deviceToken,
  }) async {
    final body = <String, dynamic>{
      'id_token': idToken,
      'authorization_code': authorizationCode,
    };
    if (deviceToken != null) {
      body['device_token'] = deviceToken;
    }

    final response = await _apiClient.post('/auth/apple', body: body);

    if (response.success && response.data != null) {
      final data = response.data;
      final tokens = data['tokens'];
      final userData = data['user'];

      await _apiClient.saveTokens(
        accessToken: tokens['access_token'],
        refreshToken: tokens['refresh_token'],
        userId: userData['id'],
      );

      final user = User.fromJson(userData);
      return AuthResult(success: true, user: user);
    }

    return AuthResult(
      success: false,
      error: response.error ?? 'Apple sign in failed',
      errorCode: response.errorCode,
    );
  }

  // Facebook Sign In
  Future<AuthResult> facebookSignIn({
    required String accessToken,
    String? deviceToken,
  }) async {
    final body = <String, dynamic>{
      'access_token': accessToken,
    };
    if (deviceToken != null) {
      body['device_token'] = deviceToken;
    }

    final response = await _apiClient.post('/auth/facebook', body: body);

    if (response.success && response.data != null) {
      final data = response.data;
      final tokens = data['tokens'];
      final userData = data['user'];

      await _apiClient.saveTokens(
        accessToken: tokens['access_token'],
        refreshToken: tokens['refresh_token'],
        userId: userData['id'],
      );

      final user = User.fromJson(userData);
      return AuthResult(success: true, user: user);
    }

    return AuthResult(
      success: false,
      error: response.error ?? 'Facebook sign in failed',
      errorCode: response.errorCode,
    );
  }

  // Refresh Token
  Future<bool> refreshToken() async {
    return await _apiClient.refreshAccessToken();
  }
}

class AuthResult {
  final bool success;
  final User? user;
  final String? message;
  final String? error;
  final String? errorCode;

  AuthResult({
    required this.success,
    this.user,
    this.message,
    this.error,
    this.errorCode,
  });
}
