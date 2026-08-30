import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flame/providers/auth_provider.dart';
import 'package:flame/services/auth_service.dart';

// Log out is the one action that must not depend on the network. The server
// call revokes refresh tokens, which is worth attempting — but if it throws,
// the user has already tapped the button and watched the dialog close. Leaving
// them signed in reads as a dead button, and it is the opposite of what they
// asked for.

class _ThrowingAuthService extends AuthService {
  int calls = 0;
  @override
  Future<void> logout() async {
    calls++;
    throw Exception('offline');
  }
}

class _WorkingAuthService extends AuthService {
  int calls = 0;
  @override
  Future<void> logout() async => calls++;
}

void main() {
  // AuthNotifier's constructor restores a session, which reaches secure
  // storage and SharedPreferences. Same setup token_storage_test uses.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('a failed server call still signs the user out', () async {
    final service = _ThrowingAuthService();
    final auth = AuthNotifier(authService: service)
      ..state = const AuthState(status: AuthStatus.authenticated);

    await auth.logout();

    expect(service.calls, 1, reason: 'the revoke is still attempted');
    expect(auth.state.status, AuthStatus.unauthenticated,
        reason: 'tapping Log out and staying logged in is the bug');
    expect(auth.state.user, isNull);
  });

  test('the ordinary path still signs out', () async {
    final service = _WorkingAuthService();
    final auth = AuthNotifier(authService: service)
      ..state = const AuthState(status: AuthStatus.authenticated);

    await auth.logout();

    expect(service.calls, 1);
    expect(auth.state.status, AuthStatus.unauthenticated);
  });
}
