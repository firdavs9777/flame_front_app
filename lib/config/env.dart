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
    'https://flame.banatalk.com/v1',
    'wss://flame.banatalk.com',
  );

  static EnvConfig get current {
    const raw = String.fromEnvironment('APP_ENV', defaultValue: '');
    if (raw.toLowerCase() == 'local') return _local;
    if (raw.toLowerCase() == 'prod') return _prod;
    // Default by build mode: debug → local, release → prod.
    const isRelease = bool.fromEnvironment('dart.vm.product');
    return isRelease ? _prod : _local;
  }
}
