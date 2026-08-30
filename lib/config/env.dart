import 'package:flutter/foundation.dart';

enum AppEnv { local, prod }

class EnvConfig {
  final AppEnv env;
  final String apiBase;
  final String wsBase;

  /// Whether the realtime chat WebSocket should connect. The socket has shipped:
  /// `flameSocket.js` runs on the shared server under the `/flame` namespace and
  /// is initialised in server.js.
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
  /// Whether the app offers password recovery. Off until /auth/forgot-password
  /// and /auth/reset-password existed server-side; both ship now, so an account
  /// created with an email is no longer permanently lost when the password is.
  final bool forgotPasswordEnabled;

  /// Whether the Chat tab is shown. The backend endpoints have shipped:
  /// /conversations (list, open, messages, read) and /messages/:id (edit,
  /// delete, reactions), plus the `/flame` socket namespace.
  ///
  /// Scope note: image and video messages, pin and mute now have routes, and
  /// the composer surfaces photo/video attachments. Two gaps remain, both
  /// deliberate — voice has a backend and a player but no recorder UI, and
  /// stickers are cut, so all five sticker endpoints still 404. Do not surface
  /// either affordance until that changes.
  final bool chatEnabled;


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
       chatEnabled = false;

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
    // Apple and Facebook are ON in local purely so the buttons can be seen and
    // reviewed while their credentials are still missing. Tapping them fails —
    // Apple has no entitlement, Facebook has placeholder native keys, and the
    // backend has neither provider's env vars. Prod deliberately keeps them off
    // so real users and App Store reviewers never reach a dead button.
    appleSignInEnabled: true,
    facebookSignInEnabled: true,
    forgotPasswordEnabled: true,
    chatEnabled: true,
  );

  static const _prod = EnvConfig._(
    AppEnv.prod,
    // Flame is served as a sub-app of the BananaTalk backend at /flamebackend/v1
    // (~/Projects/BananaTalk/backend/flame), sharing its server and socket.
    // api.flame.banatalk.com is the separate Python service and is NOT in use:
    // it resolves to 15.165.66.89 but has no listener on 80 or 443.
    'https://api.banatalk.com/flamebackend/v1',
    'wss://api.banatalk.com',
    realtimeEnabled: true,
    chatEnabled: true,
    googleSignInEnabled: true,
    appleSignInEnabled: false,
    facebookSignInEnabled: false,
    forgotPasswordEnabled: true,
  );

  /// The two shipped presets, exposed so tests can assert each one's flags
  /// directly instead of only whichever [current] resolves to.
  @visibleForTesting
  static EnvConfig get localConfig => _local;
  @visibleForTesting
  static EnvConfig get prodConfig => _prod;

  static EnvConfig get current {
    const raw = String.fromEnvironment('APP_ENV', defaultValue: '');
    if (raw.toLowerCase() == 'local') return _local;
    // Default to prod unless explicitly set to local.
    return _prod;
  }
}
