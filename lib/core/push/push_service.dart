import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:flame/config/env.dart';
import 'package:flame/core/push/device_id.dart';
import 'package:flame/core/push/push_navigator.dart';
import 'package:flame/core/push/push_payload.dart';
import 'package:flame/services/device_service.dart';

/// Push notifications: permission, device-token lifecycle, and tap routing.
///
/// **Nothing here throws into the app.** Every entry point is wrapped, because
/// a failure to set up notifications must never stop someone using Flame —
/// exactly the stance `flame/services/pushService.js` takes on the server,
/// where an unconfigured Firebase logs and returns rather than raising. A
/// crash on launch would be a far worse bug than a missing notification.
///
/// ## What this deliberately does NOT do
///
/// **It does not display anything while the app is open.** Android suppresses
/// the system tray for foreground messages and leaves it to the app, and the
/// obvious next step — adding `flutter_local_notifications` to draw a banner —
/// is not taken, for two reasons. The socket already delivers foreground chat
/// live, so the message the banner would announce is on screen as it arrives;
/// and a banner for the conversation you are currently reading is noise. If
/// in-app banners are wanted later they are an additive change to
/// [_onForegroundMessage] alone.
///
/// **It registers no background handler.** One is only required for data-only
/// messages, and the server always sends a `notification` block alongside its
/// `data`, so the OS renders the tray entry itself while the app is dead. The
/// payload is read on tap instead — see [attachHandlers].
class PushService {
  PushService({
    required PushNavigator navigator,
    FirebaseMessaging? messaging,
    DeviceService? deviceService,
  })  : _navigator = navigator,
        _messaging = messaging,
        _deviceService = deviceService ?? DeviceService();

  final PushNavigator _navigator;
  final DeviceService _deviceService;
  final FirebaseMessaging? _messaging;

  StreamSubscription<RemoteMessage>? _openedAppSub;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;

  /// Set once a token has been accepted by the backend, so a refresh knows
  /// whether there is a session to re-register under.
  bool _registered = false;

  FirebaseMessaging get _fcm => _messaging ?? FirebaseMessaging.instance;

  /// The value the backend's zod enum accepts for this device.
  ///
  /// The enum is exactly ['ios','android'] and the route is strict, so a wrong
  /// value is a 422 and the device silently never registers. Derived rather
  /// than hardcoded because the registration path is shared.
  @visibleForTesting
  static String get platformValue =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? PushPlatform.ios
          : PushPlatform.android;

  /// Whether push is wired on this build and platform.
  ///
  /// Reads the same flag that hides the notification settings screen, so the
  /// two can never disagree — a build that shows the settings screen is by
  /// definition one where a token gets registered.
  static bool get isSupported => EnvConfig.current.notificationsEnabled;

  /// Brings up the Firebase SDK. Returns whether it succeeded.
  ///
  /// Guarded on [isSupported] before anything else: on iOS there is no
  /// `GoogleService-Info.plist`, and `Firebase.initializeApp()` throws rather
  /// than returning an error when its config is missing. Calling it
  /// unconditionally would crash the app on launch on every iPhone.
  static Future<bool> initializeFirebase() async {
    if (!isSupported) return false;

    try {
      await Firebase.initializeApp();
      return true;
    } catch (error, stack) {
      debugPrint('PushService: Firebase init failed — $error');
      debugPrintStack(stackTrace: stack);
      return false;
    }
  }

  /// Subscribes to taps. Call once, at startup, regardless of auth state.
  ///
  /// Taps are delivered by two different mechanisms depending on what the app
  /// was doing, and missing either one produces a notification that appears to
  /// do nothing when tapped:
  ///
  /// - [FirebaseMessaging.onMessageOpenedApp] fires when the app was alive in
  ///   the background.
  /// - [FirebaseMessaging.getInitialMessage] returns the message that cold
  ///   started the app, once, and only if it was a tap. It must be read here
  ///   because by the time any screen builds it has already been consumed.
  Future<void> attachHandlers() async {
    if (!isSupported) return;

    try {
      _openedAppSub ??= FirebaseMessaging.onMessageOpenedApp.listen(_onTap);
      _foregroundSub ??= FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      final initial = await _fcm.getInitialMessage();
      if (initial != null) _onTap(initial);
    } catch (error) {
      debugPrint('PushService: could not attach handlers — $error');
    }
  }

  /// Asks for permission, then registers this device's token with the backend.
  ///
  /// Call once the user is authenticated: registration is an authenticated
  /// request, and a token registered against no session belongs to nobody.
  Future<void> registerDevice() async {
    if (!isSupported) return;

    try {
      // On Android 13+ this raises the POST_NOTIFICATIONS dialog; below it,
      // and on a device that has already answered, it resolves immediately.
      // On iOS it is not optional — without permission APNs never issues a
      // token, and everything below is unreachable.
      await _fcm.requestPermission();

      if (!await _awaitApnsToken()) return;

      final token = await _fcm.getToken();
      if (token == null) {
        debugPrint('PushService: no FCM token available');
        return;
      }

      await _register(token);

      // FCM rotates tokens on its own schedule, and a rotated token that is
      // never re-registered silently stops receiving anything. The old entry
      // is replaced rather than duplicated because both registrations carry
      // the same device id.
      _tokenRefreshSub ??= _fcm.onTokenRefresh.listen((refreshed) {
        if (!_registered) return;
        unawaited(_register(refreshed));
      });
    } catch (error) {
      debugPrint('PushService: device registration failed — $error');
    }
  }

  /// Removes this device's token. Call BEFORE the session is torn down —
  /// afterwards the request is unauthenticated and the token would be left
  /// behind, sending this account's notifications to a phone that signed out.
  ///
  /// A failure here is survivable rather than silent: the server prunes any
  /// token FCM later reports as unregistered, so a token stranded by a failed
  /// removal is cleaned up the first time a send to it fails.
  Future<void> unregisterDevice() async {
    if (!isSupported || !_registered) return;

    try {
      final deviceId = await DeviceId.get();
      await _deviceService.removeToken(deviceId);
    } catch (error) {
      debugPrint('PushService: token removal failed — $error');
    } finally {
      _registered = false;
    }
  }

  /// Waits for iOS to hand Firebase an APNs token. No-op on Android.
  ///
  /// This is the iOS trap. `getToken()` returns null — or throws — until APNs
  /// has registered the app, and that round trip to Apple completes some time
  /// AFTER the permission dialog is answered. Calling getToken() straight
  /// afterwards therefore works on a warm launch and fails on a cold one, so
  /// the device registers or doesn't depending on the network that morning,
  /// which is the worst kind of bug to be handed a report about.
  ///
  /// Returns false when no token arrives. The usual cause is permission being
  /// declined: APNs simply never issues one, and there is nothing to wait for.
  Future<bool> _awaitApnsToken() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return true;

    for (var attempt = 0; attempt < 10; attempt++) {
      final apns = await _fcm.getAPNSToken();
      if (apns != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    debugPrint('PushService: no APNs token after 5s — permission declined?');
    return false;
  }

  Future<void> _register(String token) async {
    final deviceId = await DeviceId.get();
    final result = await _deviceService.registerToken(
      token: token,
      platform: platformValue,
      deviceId: deviceId,
    );

    _registered = result.success;
    if (!result.success) {
      debugPrint('PushService: token rejected — ${result.error}');
    }
  }

  void _onTap(RemoteMessage message) {
    _navigator.go(PushPayload.fromData(message.data));
  }

  /// Foreground messages are received but deliberately not displayed — see the
  /// class doc. Kept as a named seam so the decision is visible rather than
  /// implied by an absent listener.
  void _onForegroundMessage(RemoteMessage message) {}

  void dispose() {
    _openedAppSub?.cancel();
    _foregroundSub?.cancel();
    _tokenRefreshSub?.cancel();
    _openedAppSub = null;
    _foregroundSub = null;
    _tokenRefreshSub = null;
  }
}
