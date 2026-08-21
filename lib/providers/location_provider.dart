import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/providers/user_provider.dart';
import 'package:flame/services/location_service.dart';

/// Whether we can offer distance-based filtering at all.
enum LocationAvailability { unknown, granted, denied }

/// Refreshes the stored location at most once per app session.
///
/// Registration requires location, so most accounts already have a point; this
/// keeps it current as people move. Deliberately fire-and-forget: location is
/// enrichment, and the deck must never wait on it or fail because of it.
///
/// Once per session rather than once per open, because asking on every open is
/// nagging and a refusal is a decision worth respecting until the next launch.
class LocationRefresher {
  LocationRefresher({required this.getPosition, required this.push});

  /// The one thing this needs from LocationService, taken as a function rather
  /// than the service itself: LocationService is a singleton with a private
  /// constructor, so it cannot be subclassed for a test.
  final Future<LocationResult> Function() getPosition;

  final Future<bool> Function(double latitude, double longitude) push;

  LocationAvailability _availability = LocationAvailability.unknown;
  bool _attempted = false;

  LocationAvailability get availability => _availability;

  Future<void> refreshOnce() async {
    if (_attempted) return;
    _attempted = true;

    final result = await getPosition();
    if (!result.success || result.latitude == null || result.longitude == null) {
      // Recorded rather than swallowed: the filter sheet needs this to disable
      // the distance slider with a reason instead of offering a control that
      // cannot work.
      _availability = LocationAvailability.denied;
      return;
    }

    _availability = LocationAvailability.granted;
    // A failed PATCH changes nothing the user can see: the point stored at
    // registration stands, and we try again next session.
    await push(result.latitude!, result.longitude!);
  }
}

final locationRefresherProvider = Provider<LocationRefresher>((ref) {
  return LocationRefresher(
    getPosition: LocationService().getCurrentPosition,
    push: (lat, lng) =>
        ref.read(currentUserProvider.notifier).updateLocation(lat, lng),
  );
});
