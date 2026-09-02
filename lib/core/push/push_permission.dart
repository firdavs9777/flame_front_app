import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:flame/config/env.dart';

/// Whether this device will actually display a notification.
///
/// Distinct from the in-app switches, which say what the user WANTS. This says
/// what the operating system will allow, and the two can disagree — someone
/// who declined the prompt, or who granted it and later revoked it in system
/// settings, has every in-app switch on and receives nothing.
enum PushPermissionStatus {
  /// Notifications will be shown.
  authorized,

  /// iOS only: delivered quietly to the notification centre without alerting.
  /// Treated as working, because they do arrive.
  provisional,

  /// Declined, revoked, or never answered. All three mean nothing is shown,
  /// and all three are fixed in the same place — the system settings screen.
  denied,

  /// Could not be determined: Firebase is not initialised, or the platform
  /// has no notion of notification permission. Shows no banner rather than
  /// guessing, since a false warning is worse than none.
  unknown,
}

/// Reads the OS notification permission, and opens the screen that changes it.
///
/// A thin wrapper so the settings widget never imports `firebase_messaging`,
/// and so tests can substitute a status without a platform channel.
class PushPermission {
  const PushPermission({FirebaseMessaging? messaging}) : _messaging = messaging;

  final FirebaseMessaging? _messaging;

  FirebaseMessaging get _fcm => _messaging ?? FirebaseMessaging.instance;

  Future<PushPermissionStatus> status() async {
    if (!EnvConfig.current.notificationsEnabled) {
      return PushPermissionStatus.unknown;
    }

    try {
      final settings = await _fcm.getNotificationSettings();
      switch (settings.authorizationStatus) {
        case AuthorizationStatus.authorized:
          return PushPermissionStatus.authorized;
        case AuthorizationStatus.provisional:
          return PushPermissionStatus.provisional;
        case AuthorizationStatus.denied:
        case AuthorizationStatus.deniedPermanently:
        case AuthorizationStatus.notDetermined:
          // deniedPermanently is grouped here too: the app can no longer
          // re-prompt, which makes system settings not merely the best route
          // but the only one — exactly what the banner offers.
          // notDetermined is grouped with denied deliberately. It should be
          // rare — registerDevice() prompts at sign-in — but if the prompt was
          // dismissed rather than answered, nothing is displayed, which is the
          // user-visible fact this enum is about. System settings is still
          // where they turn it on.
          return PushPermissionStatus.denied;
      }
    } catch (error) {
      // Firebase not initialised, or no platform implementation. Say unknown
      // rather than denied: warning someone their notifications are off when
      // we simply could not tell is worse than staying quiet.
      debugPrint('PushPermission: could not read status — $error');
      return PushPermissionStatus.unknown;
    }
  }

  /// Opens the OS settings page for this app. Best effort — never throws.
  Future<void> openSystemSettings() async {
    try {
      await openAppSettings();
    } catch (error) {
      debugPrint('PushPermission: could not open system settings — $error');
    }
  }
}

/// Whether [status] means the user is not receiving notifications and can fix
/// it themselves. Drives whether the settings screen warns.
bool pushIsBlocked(PushPermissionStatus status) =>
    status == PushPermissionStatus.denied;
