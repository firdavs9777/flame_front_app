import 'package:flutter_test/flutter_test.dart';
import 'package:flame/providers/auth_provider.dart';

// On startup the app fetches /users/me to restore the session. It used to log
// out — discarding the refresh token — whenever that call failed for ANY
// reason, so a flaky network or a brief server error kicked a signed-in user
// back to the welcome screen and made them sign in again.
//
// Only an authoritative answer from the server ("this session is not valid")
// should clear stored credentials.

void main() {
  group('shouldClearSession', () {
    test('clears on 401 — the token is rejected', () {
      expect(AuthNotifier.shouldClearSession(401), isTrue);
    });

    test('clears on 404 — the user no longer exists or is deleted', () {
      expect(AuthNotifier.shouldClearSession(404), isTrue);
    });

    test('clears on 403 — the session is refused', () {
      expect(AuthNotifier.shouldClearSession(403), isTrue);
    });

    test('KEEPS the session on server errors', () {
      for (final code in [500, 502, 503, 504]) {
        expect(
          AuthNotifier.shouldClearSession(code),
          isFalse,
          reason: '$code is the server failing, not the session being invalid',
        );
      }
    });

    test('KEEPS the session when the request never reached the server', () {
      // ApiClient reports statusCode 0 for transport failures (no network,
      // DNS failure, timeout). These say nothing about session validity.
      expect(AuthNotifier.shouldClearSession(0), isFalse);
    });

    test('KEEPS the session on rate limiting', () {
      expect(AuthNotifier.shouldClearSession(429), isFalse);
    });
  });
}
