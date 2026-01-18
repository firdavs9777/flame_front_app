import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/user.dart';
import 'package:flame/services/auth_service.dart';

enum AuthStatus {
  initial,
  unauthenticated,
  authenticated,
  registering,
}

class AuthState {
  final AuthStatus status;
  final User? user;
  final String? error;
  final bool isLoading;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.error,
    this.isLoading = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? error,
    bool? isLoading,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService = AuthService();

  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  // Initialize and check for existing session
  Future<void> _init() async {
    await _authService.init();

    if (_authService.isLoggedIn) {
      // Try to get current user
      state = state.copyWith(isLoading: true);
      final result = await _authService.getCurrentUser();

      if (result.success && result.user != null) {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: result.user,
          isLoading: false,
        );
      } else {
        // Token invalid, logout
        await _authService.logout();
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          isLoading: false,
        );
      }
    } else {
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  // Login
  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await _authService.login(
      email: email,
      password: password,
    );

    if (result.success && result.user != null) {
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: result.user,
        isLoading: false,
      );
      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        error: result.error ?? 'Login failed',
      );
      return false;
    }
  }

  // Register
  Future<bool> register({
    required String email,
    required String password,
    required String name,
    required int age,
    required Gender gender,
    required Gender lookingFor,
    required String bio,
    required List<String> interests,
    required List<String> photos,
    required double latitude,
    required double longitude,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await _authService.register(
      email: email,
      password: password,
      name: name,
      age: age,
      gender: gender,
      lookingFor: lookingFor,
      bio: bio,
      interests: interests,
      photos: photos,
      latitude: latitude,
      longitude: longitude,
    );

    if (result.success && result.user != null) {
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: result.user,
        isLoading: false,
      );
      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        error: result.error ?? 'Registration failed',
      );
      return false;
    }
  }

  // Start registration flow
  void startRegistration() {
    state = state.copyWith(status: AuthStatus.registering);
  }

  // Cancel registration
  void cancelRegistration() {
    state = state.copyWith(status: AuthStatus.unauthenticated);
  }

  // Logout
  Future<void> logout() async {
    await _authService.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  // Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }

  // Update user locally (after profile update)
  void updateUser(User user) {
    state = state.copyWith(user: user);
  }

  // Forgot password
  Future<bool> forgotPassword(String email) async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await _authService.forgotPassword(email);

    state = state.copyWith(
      isLoading: false,
      error: result.success ? null : result.error,
    );

    return result.success;
  }

  // Change password
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await _authService.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );

    state = state.copyWith(
      isLoading: false,
      error: result.success ? null : result.error,
    );

    return result.success;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
