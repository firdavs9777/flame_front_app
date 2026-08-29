import 'package:flame/services/location_service.dart';

/// Why establishing the coordinates failed, so the caller can word the message.
enum LocationGateFailure {
  /// The device would not give us a fix — usually a refused permission.
  position,

  /// We have coordinates but the server did not accept them.
  push,
}

class LocationGateResult {
  final bool ok;
  final LocationGateFailure? failure;

  /// The device's reason, when [failure] is [LocationGateFailure.position].
  final String? error;

  const LocationGateResult._({required this.ok, this.failure, this.error});

  const LocationGateResult.ok() : this._(ok: true);

  const LocationGateResult.failed(LocationGateFailure failure, [String? error])
      : this._(ok: false, failure: failure, error: error);
}

/// Establishes the coordinates a profile needs before it can count as complete.
///
/// The backend calls a profile complete only when photos AND a non-empty
/// interest AND location coordinates are all present (flame_backend
/// `app/core/profile.py`). Registration satisfies that by sending coordinates
/// with /auth/register. A social signup has none — the account is created from
/// the provider's token alone — so its completion flow has to establish them
/// itself.
///
/// It cannot lean on [LocationRefresher] for this. That is enrichment for
/// accounts that already have a point: it attempts once per session, ignores a
/// failed PATCH on purpose, and only runs if the user reaches Discover. Fine
/// for keeping a point current, not enough to create the first one.
///
/// Both dependencies are functions rather than the services themselves:
/// LocationService is a singleton with a private constructor and cannot be
/// subclassed for a test.
class LocationGate {
  const LocationGate();

  Future<LocationGateResult> establish({
    required Future<LocationResult> Function() getPosition,
    required Future<bool> Function(double latitude, double longitude) push,
  }) async {
    final position = await getPosition();
    if (!position.success ||
        position.latitude == null ||
        position.longitude == null) {
      return LocationGateResult.failed(
        LocationGateFailure.position,
        position.error,
      );
    }

    final pushed = await push(position.latitude!, position.longitude!);
    if (!pushed) {
      return const LocationGateResult.failed(LocationGateFailure.push);
    }

    return const LocationGateResult.ok();
  }
}
