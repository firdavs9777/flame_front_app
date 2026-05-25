import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/user.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/auth_service.dart';
import 'package:flame/services/billing_service.dart';

enum AuthStatus {
  initial,
  unauthenticated,
  authenticated,
  registering,
  profileIncomplete,
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
  bool get isProfileIncomplete => status == AuthStatus.profileIncomplete;
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService = AuthService();
  final BillingService _billingService = BillingService();

  AuthNotifier() : super(const AuthState()) {
    // Wire the ApiClient's session-lost signal so refresh-failure / revoked
    // tokens / server-side logouts immediately flip the app to the login
    // screen without waiting for the next user action.
    ApiClient().onAuthLost = _handleAuthLost;
    _init();
  }

  Future<void> _handleAuthLost() async {
    if (state.status == AuthStatus.unauthenticated) return;
    await _authService.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  // Decides which post-auth screen the user belongs on. Prefers the backend's
  // server-evaluated is_profile_complete; falls back to a local heuristic for
  // older API versions / during the deploy window where the field is missing.
  AuthStatus _statusFor(User user) {
    final complete = user.isProfileComplete ??
        (user.photos.isNotEmpty && user.interests.isNotEmpty);
    return complete ? AuthStatus.authenticated : AuthStatus.profileIncomplete;
  }

  // Initialize and check for existing session
  Future<void> _init() async {
    await _authService.init();

    if (_authService.isLoggedIn) {
      // Try to get current user
      state = state.copyWith(isLoading: true);
      final result = await _authService.getCurrentUser();

      if (result.success && result.user != null) {
        final user = await _withPremiumFromBilling(result.user!);
        state = state.copyWith(
          status: _statusFor(user),
          user: user,
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

  // Fetches billing status from the backend and returns a copy of [user] with
  // isPremium and premiumExpiresAt updated. If the billing call fails, the
  // original user is returned unchanged — billing is non-critical for login.
  Future<User> _withPremiumFromBilling(User user) async {
    final status = await _billingService.getStatus();
    if (!status.isKnown) return user;
    return user.copyWith(
      isPremium: status.isPremium,
      premiumExpiresAt: status.expiresAt,
    );
  }

  // Public method so screens (e.g., settings, profile) can refresh premium
  // state after a purchase or when the user pulls-to-refresh.
  Future<void> refreshBillingStatus() async {
    final user = state.user;
    if (user == null) return;
    final updated = await _withPremiumFromBilling(user);
    state = state.copyWith(user: updated);
  }

  // Login
  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await _authService.login(
      email: email,
      password: password,
    );

    if (result.success && result.user != null) {
      final user = await _withPremiumFromBilling(result.user!);
      state = state.copyWith(
        status: _statusFor(user),
        user: user,
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
      final user = await _withPremiumFromBilling(result.user!);
      state = state.copyWith(
        status: _statusFor(user),
        user: user,
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

  // Social login (Google / Apple / Facebook)
  Future<bool> socialLogin({
    String? googleIdToken,
    String? appleIdToken,
    String? appleAuthorizationCode,
    String? facebookAccessToken,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    AuthResult result;

    if (googleIdToken != null) {
      result = await _authService.googleSignIn(idToken: googleIdToken);
    } else if (appleIdToken != null && appleAuthorizationCode != null) {
      result = await _authService.appleSignIn(
        idToken: appleIdToken,
        authorizationCode: appleAuthorizationCode,
      );
    } else if (facebookAccessToken != null) {
      result = await _authService.facebookSignIn(accessToken: facebookAccessToken);
    } else {
      state = state.copyWith(isLoading: false, error: 'No social token provided');
      return false;
    }

    if (result.success && result.user != null) {
      final user = await _withPremiumFromBilling(result.user!);
      state = state.copyWith(
        status: _statusFor(user),
        user: user,
        isLoading: false,
      );
      return true;
    }

    state = state.copyWith(
      isLoading: false,
      error: result.error ?? 'Social login failed',
    );
    return false;
  }

  // Promote profileIncomplete user to authenticated (after completion flow)
  void markAuthenticated() {
    state = state.copyWith(status: AuthStatus.authenticated);
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
