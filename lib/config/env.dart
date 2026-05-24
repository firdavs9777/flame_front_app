enum AppEnv { local, prod }

class EnvConfig {
  final AppEnv env;
  final String apiBase;
  final String wsBase;

  const EnvConfig._(this.env, this.apiBase, this.wsBase);

  static const _local = EnvConfig._(
    AppEnv.local,
    'http://localhost:8000/v1',
    'ws://localhost:8000',
  );

  static const _prod = EnvConfig._(
    AppEnv.prod,
    'https://api.flame.banatalk.com/v1',
    'wss://api.flame.banatalk.com',
  );

  static EnvConfig get current {
    const raw = String.fromEnvironment('APP_ENV', defaultValue: '');
    if (raw.toLowerCase() == 'local') return _local;
    // Default to prod unless explicitly set to local.
    return _prod;
  }
}
