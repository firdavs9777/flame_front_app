import 'dart:convert';
import '../services/api_client.dart';

/// Immutable snapshot of runtime configuration fetched from the backend
/// `/v1/config` endpoint. Defaults are fail-safe (legacy paths only).
class RuntimeConfig {
  final bool chatV2Enabled;
  const RuntimeConfig({required this.chatV2Enabled});
}

/// Fetches and caches runtime configuration from the backend. The cache
/// defaults to a fail-safe value (chatV2Enabled=false) so the legacy chat
/// path is selected if the backend is unreachable.
class RuntimeConfigService {
  final ApiClient api;
  RuntimeConfigService(this.api);

  RuntimeConfig _cached = const RuntimeConfig(chatV2Enabled: false);
  RuntimeConfig get current => _cached;

  /// Fetches `/config` and updates the cached snapshot. On failure (network
  /// error, non-success response, malformed body) the previous cached value
  /// is returned unchanged.
  Future<RuntimeConfig> fetch() async {
    final resp = await api.get('/config');
    if (!resp.success || resp.data == null) {
      return _cached;
    }
    final raw = resp.data;
    final body = raw is String ? jsonDecode(raw) : raw;
    final enabled = (body is Map && body['chat_v2_enabled'] == true);
    _cached = RuntimeConfig(chatV2Enabled: enabled);
    return _cached;
  }
}
