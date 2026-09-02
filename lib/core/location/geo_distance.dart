import 'dart:math' as math;

const double _earthRadiusKm = 6371.0;

/// Great-circle distance in kilometres between two coordinates.
///
/// Written here rather than taken from Geolocator so it is pure Dart: this is
/// used to decide whether a stored location has gone stale, which must work in
/// a unit test without a platform channel.
///
/// Haversine, matching the backend's `haversineKm` in discoveryService — the
/// two are compared against each other only loosely (a "did they move?"
/// threshold), but agreeing on the formula means they cannot disagree about
/// what a kilometre is.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  double toRad(double d) => d * math.pi / 180.0;

  final dLat = toRad(lat2 - lat1);
  final dLng = toRad(lng2 - lng1);

  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(toRad(lat1)) *
          math.cos(toRad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);

  return 2 * _earthRadiusKm * math.asin(math.sqrt(h.toDouble()));
}
