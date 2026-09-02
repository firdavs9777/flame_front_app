import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/push/push_service.dart';
import 'package:flame/services/device_service.dart';

/// The backend validates `platform` with a strict zod enum of exactly
/// ['ios','android']. A wrong or misspelled value is a 422, and because
/// registration failures are logged rather than surfaced, the symptom would be
/// a whole platform silently never receiving a notification.
void main() {
  test('iOS registers as ios', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(PushService.platformValue, PushPlatform.ios);
    expect(PushService.platformValue, 'ios');
  });

  test('Android registers as android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(PushService.platformValue, PushPlatform.android);
    expect(PushService.platformValue, 'android');
  });

  test('only ever emits a value the enum accepts', () {
    // Including the platforms Flame does not ship, so a desktop or web build
    // cannot produce a third value that fails validation.
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        PushService.platformValue,
        anyOf(PushPlatform.ios, PushPlatform.android),
        reason: '$platform produced a value the backend would reject',
      );
    }
    debugDefaultTargetPlatformOverride = null;
  });
}
