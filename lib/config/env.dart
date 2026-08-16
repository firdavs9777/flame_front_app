import 'package:flutter/foundation.dart';

enum AppEnv { local, prod }

class EnvConfig {
  final AppEnv env;
  final String apiBase;
  final String wsBase;

  /// Whether the realtime chat WebSocket should connect. The Flame backend has
  /// no chat socket yet, so this is off in prod to avoid an endless reconnect
  /// loop. Flip to true once the socket server ships.
  final bool realtimeEnabled;

  /// Social login is gated per provider, not all-or-nothing: the backend
  /// endpoints (/auth/google, /auth/apple, /auth/facebook) are all live, but
  /// each provider also needs native credentials before its button can work.
  /// Turning one on without those makes the button fail at tap time, so each
  /// flag flips only once its native setup lands. See docs/social-auth-setup.md.

  /// Google Sign-In. On — iOS has its client ID, URL scheme and serverClientId
  /// wired in Info.plist. Android needs no files, only an Android OAuth client
  /// (package + SHA-1) registered in Google Cloud; until that exists Android
  /// returns a sign-in error while iOS works.
  final bool googleSignInEnabled;

  /// Sign in with Apple. Off — the "Sign in with Apple" capability and a
  /// Runner.entitlements file do not exist yet, so it fails on device.
  /// NOTE: App Store guideline 4.8 requires this before submitting an iOS
  /// build that offers any other third-party login.
  final bool appleSignInEnabled;

  /// Facebook Login. Off — Info.plist still holds YOUR_FACEBOOK_APP_ID /
  /// YOUR_FACEBOOK_CLIENT_TOKEN placeholders and Android has no Facebook
  /// manifest or strings entries at all.
  final bool facebookSignInEnabled;

  /// True when at least one provider is live. Drives the "Or continue with"
  /// divider and any screen that asks "is there social login at all?".
  bool get authSocialEnabled =>
      googleSignInEnabled || appleSignInEnabled || facebookSignInEnabled;

  /// Whether the forgot-password flow is shown. No /auth/forgot-password on the
  /// backend yet — off until it ships.
  final bool forgotPasswordEnabled;

  /// Whether the Chat tab is shown. Off in prod until the Flame backend chat
  /// endpoints ship; on locally for development.
  final bool chatEnabled;

  /// Whether the advanced Discover filters (gender / interests / online-only)
  /// are shown. Off until the backend actually honors them — today only age +
  /// distance are applied, so showing the others would be a no-op that lies.
  final bool advancedFiltersEnabled;

  const EnvConfig._(
    this.env,
    this.apiBase,
    this.wsBase, {
    this.realtimeEnabled = true,
    this.googleSignInEnabled = false,
    this.appleSignInEnabled = false,
    this.facebookSignInEnabled = false,
    this.forgotPasswordEnabled = false,
    this.chatEnabled = false,
    this.advancedFiltersEnabled = false,
  });

  /// Test-only seam for exercising flag combinations that no real environment
  /// ships today (e.g. Apple enabled, to prove the Android platform guard).
  @visibleForTesting
  const EnvConfig.testing({
    this.googleSignInEnabled = false,
    this.appleSignInEnabled = false,
    this.facebookSignInEnabled = false,
  }) : env = AppEnv.local,
       apiBase = '',
       wsBase = '',
       realtimeEnabled = false,
       forgotPasswordEnabled = false,
       chatEnabled = false,
       advancedFiltersEnabled = false;

  // For iOS Simulator use `localhost`; for a physical device use the Mac's LAN IP.
  // Switch by passing `--dart-define=LOCAL_HOST=192.168.100.114` at run time,
  // or edit the fallback string below.
  static const _localHost = String.fromEnvironment(
    'LOCAL_HOST',
    defaultValue: '192.168.100.114',
  );

  static const _local = EnvConfig._(
    AppEnv.local,
    'http://$_localHost:8000/v1',
    'ws://$_localHost:8000',
    googleSignInEnabled: true,
    appleSignInEnabled: false,
    facebookSignInEnabled: false,
    forgotPasswordEnabled: false,
    chatEnabled: true,
  );

  static const _prod = EnvConfig._(
    AppEnv.prod,
    // Flame is served as a sub-app of the BananaTalk backend at /flamebackend/v1.
    // The api.flame.banatalk.com host currently has an SSL cert mismatch (causes
    // HandshakeException on login), so we hit the working, valid-cert host.
    'https://api.banatalk.com/flamebackend/v1',
    'wss://api.banatalk.com',
    realtimeEnabled: false, // no chat socket on the Flame backend yet
    googleSignInEnabled: true,
    appleSignInEnabled: false,
    facebookSignInEnabled: false,
    forgotPasswordEnabled: false,
    advancedFiltersEnabled: false,
  );

  static EnvConfig get current {
    const raw = String.fromEnvironment('APP_ENV', defaultValue: '');
    if (raw.toLowerCase() == 'local') return _local;
    // Default to prod unless explicitly set to local.
    return _prod;
  }
}
