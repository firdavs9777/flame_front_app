import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A stable id for this installation, used as the key the backend upserts
/// device tokens by.
///
/// `deviceService.registerToken` finds an existing entry by `deviceId` and
/// replaces its token rather than appending. That de-duplication is the whole
/// point: FCM hands out a new token after a reinstall, a data clear, or its own
/// periodic rotation, and without a stable key every rotation would leave a
/// dead token behind and the user would receive one push per historical token
/// until FCM reported each as unregistered.
///
/// Stored in [SharedPreferences] rather than secure storage: it is not a
/// secret, it identifies a device rather than a person, and it must survive
/// logout — the same phone signing back in should reclaim its own token entry
/// instead of stranding one.
///
/// It does NOT survive an uninstall, which is correct — a reinstall gets a new
/// FCM token anyway, and the old entry is pruned server-side the first time a
/// send to it fails.
abstract final class DeviceId {
  static const storageKey = 'flame_device_id';

  static const _uuid = Uuid();

  /// Returns this install's id, generating and persisting one on first call.
  static Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();

    final existing = prefs.getString(storageKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _uuid.v4();
    await prefs.setString(storageKey, generated);
    return generated;
  }
}
