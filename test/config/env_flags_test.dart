import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/config/env.dart';

void main() {
  test('forgot-password is ON in both environments', () {
    // Was off in both presets because /auth/forgot-password and
    // /auth/reset-password did not exist server-side. Anyone who registered
    // with an email and forgot the password was locked out permanently, with no
    // support path back. Both routes ship now.
    expect(EnvConfig.prodConfig.forgotPasswordEnabled, isTrue);
    expect(EnvConfig.localConfig.forgotPasswordEnabled, isTrue);
  });

  test('chat and its socket are ON in both environments', () {
    // /conversations + /messages and the `/flame` socket namespace have all
    // shipped. Text-only: media/stickers/pin/mute have no backend routes, and
    // the reachable composer deliberately does not offer them.
    expect(EnvConfig.prodConfig.chatEnabled, isTrue);
    expect(EnvConfig.prodConfig.realtimeEnabled, isTrue);
    expect(EnvConfig.localConfig.chatEnabled, isTrue);
  });

  group('prod', () {
    test('ships the two providers that work end to end', () {
      expect(EnvConfig.prodConfig.googleSignInEnabled, isTrue);
      // Apple was off while it had no entitlement and the server had no
      // FLAME_APPLE_CLIENT_ID. Both are now true — the entitlement is in the
      // signed binary and /auth/apple rejects a junk token with
      // INVALID_SOCIAL_TOKEN rather than 501 PROVIDER_NOT_CONFIGURED.
      //
      // It is also required: Guideline 4.8 does not allow offering Google
      // without Sign in with Apple, so these two flags move together.
      expect(EnvConfig.prodConfig.appleSignInEnabled, isTrue);
    });

    test('offers notifications on Android, where a push can arrive', () {
      // firebase_messaging is a dependency, android/app/google-services.json
      // exists, PushService registers a device token, and the server has
      // FLAME_FIREBASE_PROJECT_ID set.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(EnvConfig.prodConfig.notificationsEnabled, isTrue);
      expect(EnvConfig.localConfig.notificationsEnabled, isTrue);
    });

    test('keeps notifications OFF on iOS, which cannot receive one', () {
      // No iOS app in Firebase, no GoogleService-Info.plist, no APNs key. The
      // build flag is on; the platform is what withholds it. Offering settings
      // for deliveries that cannot happen is worse than offering nothing.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(EnvConfig.prodConfig.notificationsEnabled, isFalse);
      expect(EnvConfig.localConfig.notificationsEnabled, isFalse);

      // The build half stays true, so flipping iOS on later is one deletion in
      // env.dart rather than a hunt for which flag was turned off and why.
      expect(EnvConfig.prodConfig.pushConfigured, isTrue);
    });

    test('keeps Facebook OFF so no user hits a dead button', () {
      // Placeholder native keys, and the backend has no FLAME_FACEBOOK_APP_ID
      // or _SECRET — the button would authenticate and then fail at the server.
      expect(EnvConfig.prodConfig.facebookSignInEnabled, isFalse);
    });
  });

  group('local', () {
    test('shows all three so the buttons can be reviewed in dev', () {
      expect(EnvConfig.localConfig.googleSignInEnabled, isTrue);
      expect(EnvConfig.localConfig.appleSignInEnabled, isTrue);
      expect(EnvConfig.localConfig.facebookSignInEnabled, isTrue);
    });
  });

  test('authSocialEnabled is derived from the per-provider flags', () {
    expect(EnvConfig.current.authSocialEnabled, isTrue);
    expect(
      const EnvConfig.testing().authSocialEnabled,
      isFalse,
      reason: 'no providers on means no social section at all',
    );
  });
}
