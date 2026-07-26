enum AppEnv { local, prod }

class EnvConfig {
  final AppEnv env;
  final String apiBase;
  final String wsBase;

  /// Whether the realtime chat WebSocket should connect. The Flame backend has
  /// no chat socket yet, so this is off in prod to avoid an endless reconnect
  /// loop. Flip to true once the socket server ships.
  final bool realtimeEnabled;

  /// Whether social login (Google/Apple/Facebook) is shown. The Flame backend
  /// has no social auth endpoints yet — off until they ship.
  final bool authSocialEnabled;

  /// Whether the forgot-password flow is shown. No /auth/forgot-password on the
  /// backend yet — off until it ships.
  final bool forgotPasswordEnabled;

  /// Whether the Chat tab is shown. Off in prod until the Flame backend chat
  /// endpoints ship; on locally for development.
  final bool chatEnabled;

  const EnvConfig._(this.env, this.apiBase, this.wsBase,
      {this.realtimeEnabled = true,
      this.authSocialEnabled = false,
      this.forgotPasswordEnabled = false,
      this.chatEnabled = false});

  // For iOS Simulator use `localhost`; for a physical device use the Mac's LAN IP.
  // Switch by passing `--dart-define=LOCAL_HOST=192.168.100.114` at run time,
  // or edit the fallback string below.
  static const _localHost = String.fromEnvironment('LOCAL_HOST', defaultValue: '192.168.100.114');

  static const _local = EnvConfig._(
    AppEnv.local,
    'http://$_localHost:8000/v1',
    'ws://$_localHost:8000',
    authSocialEnabled: false,
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
    authSocialEnabled: false,
    forgotPasswordEnabled: false,
  );

  static EnvConfig get current {
    const raw = String.fromEnvironment('APP_ENV', defaultValue: '');
    if (raw.toLowerCase() == 'local') return _local;
    // Default to prod unless explicitly set to local.
    return _prod;
  }
}
