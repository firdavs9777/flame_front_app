import 'package:flutter_test/flutter_test.dart';
import 'package:flame/config/env.dart';

void main() {
  test('forgot-password and chat stay OFF by default (MVP)', () {
    expect(EnvConfig.current.forgotPasswordEnabled, isFalse);
    expect(EnvConfig.current.chatEnabled, isFalse);
  });

  test('Google sign-in is ON — backend /auth/google and iOS keys are live', () {
    expect(EnvConfig.current.googleSignInEnabled, isTrue);
  });

  test('Apple and Facebook stay OFF until their native config lands', () {
    // Apple needs the Sign in with Apple entitlement/capability; Facebook needs
    // real Meta App ID + Client Token. See docs/social-auth-setup.md.
    expect(EnvConfig.current.appleSignInEnabled, isFalse);
    expect(EnvConfig.current.facebookSignInEnabled, isFalse);
  });

  test('authSocialEnabled is derived from the per-provider flags', () {
    expect(EnvConfig.current.authSocialEnabled, isTrue);
  });
}
