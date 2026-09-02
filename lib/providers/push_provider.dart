import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/navigation/app_router.dart';
import 'package:flame/core/push/push_navigator.dart';
import 'package:flame/core/push/push_service.dart';

/// The app's single [PushService].
///
/// One instance, because it owns stream subscriptions — a second would attach
/// a second tap listener and navigate twice for one notification.
final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(navigator: PushNavigator(appNavigatorKey));
  ref.onDispose(service.dispose);
  return service;
});
