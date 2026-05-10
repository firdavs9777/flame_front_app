import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';
import '../services/runtime_config_service.dart';

/// Exposes the singleton [ApiClient] via Riverpod. Kept here (rather than in
/// `lib/realtime/providers.dart`) to avoid touching the existing realtime
/// providers file.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final runtimeConfigServiceProvider = Provider<RuntimeConfigService>((ref) {
  return RuntimeConfigService(ref.read(apiClientProvider));
});

/// Resolves to true when the backend has rolled out chat_v2 for this client.
/// Defaults to false on any fetch failure (legacy chat path).
final chatV2EnabledProvider = FutureProvider<bool>((ref) async {
  final svc = ref.read(runtimeConfigServiceProvider);
  final cfg = await svc.fetch();
  return cfg.chatV2Enabled;
});
