import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/config/env.dart';
import 'package:flame/widgets/auth/social_sign_in_buttons.dart';

void main() {
  group('SocialProviderVisibility.forEnv', () {
    test('mirrors the env flags on iOS', () {
      final v = SocialProviderVisibility.forEnv(
        EnvConfig.current,
        TargetPlatform.iOS,
      );

      expect(v.google, EnvConfig.current.googleSignInEnabled);
      expect(v.apple, EnvConfig.current.appleSignInEnabled);
      expect(v.facebook, EnvConfig.current.facebookSignInEnabled);
    });

    test('hides Apple on Android even when the env flag is on', () {
      // signInWithApple() passes no webAuthenticationOptions, so the Apple
      // button cannot work on Android regardless of credentials.
      const env = EnvConfig.testing(
        googleSignInEnabled: true,
        appleSignInEnabled: true,
        facebookSignInEnabled: true,
      );

      final android =
          SocialProviderVisibility.forEnv(env, TargetPlatform.android);
      expect(android.apple, isFalse);
      expect(android.google, isTrue);
      expect(android.facebook, isTrue);

      final ios = SocialProviderVisibility.forEnv(env, TargetPlatform.iOS);
      expect(ios.apple, isTrue);
    });

    test('any is false only when every provider is off', () {
      const off = SocialProviderVisibility();
      expect(off.any, isFalse);

      const googleOnly = SocialProviderVisibility(google: true);
      expect(googleOnly.any, isTrue);
    });
  });
}
