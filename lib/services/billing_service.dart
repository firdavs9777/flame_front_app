import 'api_client.dart';

/// Talks to the backend billing endpoints.
///
/// Only `getStatus()` is implemented — the apple/google verify endpoints
/// return 403 stubs on the backend today and will be wired up when IAP
/// (in_app_purchase / purchases_flutter) is integrated.
class BillingService {
  final ApiClient _apiClient = ApiClient();

  Future<BillingStatus> getStatus() async {
    final response = await _apiClient.get('/billing/status');
    if (!response.success || response.data == null) {
      return BillingStatus.unknown(error: response.error);
    }
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      return BillingStatus.unknown(error: 'Unexpected billing status payload');
    }
    return BillingStatus.fromJson(data);
  }
}

/// Snapshot of the user's premium/subscription state.
///
/// Field names assume snake_case keys from the backend. If the actual API
/// shape differs, adjust the keys in [fromJson] — the rest of the app only
/// reads [isPremium] and [expiresAt].
class BillingStatus {
  final bool isPremium;
  final DateTime? expiresAt;
  final String? tier;
  final String? subscriptionId;
  final String? error;

  const BillingStatus({
    required this.isPremium,
    this.expiresAt,
    this.tier,
    this.subscriptionId,
    this.error,
  });

  factory BillingStatus.fromJson(Map<String, dynamic> json) {
    final expiresRaw = json['expires_at'] ?? json['expiresAt'];
    return BillingStatus(
      isPremium: (json['is_premium'] ?? json['isPremium'] ?? false) as bool,
      expiresAt: expiresRaw is String ? DateTime.tryParse(expiresRaw) : null,
      tier: json['tier'] as String?,
      subscriptionId:
          (json['subscription_id'] ?? json['subscriptionId']) as String?,
    );
  }

  factory BillingStatus.unknown({String? error}) {
    return BillingStatus(isPremium: false, error: error);
  }

  bool get isKnown => error == null;
}
