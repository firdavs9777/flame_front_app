import 'package:flutter_test/flutter_test.dart';
import 'package:flame/config/env.dart';

void main() {
  test('forgot-password stays OFF — no backend endpoint for it', () {
    expect(EnvConfig.current.forgotPasswordEnabled, isFalse);
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
    test('ships Google only — the one provider that works end to end', () {
      expect(EnvConfig.prodConfig.googleSignInEnabled, isTrue);
    });

    test('keeps Apple and Facebook OFF so no user hits a dead button', () {
      // Apple lacks its entitlement, Facebook has placeholder native keys, and
      // the backend has neither provider's env vars. Showing them in prod would
      // also fail App Store review. See docs/social-auth-setup.md.
      expect(EnvConfig.prodConfig.appleSignInEnabled, isFalse);
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
