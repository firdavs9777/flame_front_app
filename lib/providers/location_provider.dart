import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/location/geo_distance.dart';
import 'package:flame/core/location/place_resolver.dart';
import 'package:flame/providers/user_provider.dart';
import 'package:flame/services/location_service.dart';

/// Whether we can offer distance-based filtering at all.
/// What the app currently knows about its ability to read a location.
///
/// [denied] and [unavailable] are both "no coordinates right now" and are
/// deliberately NOT the same thing. Only a refusal is worth remembering: a
/// failed fix is worth retrying, and describing it as a permission problem
/// tells the user to go and change a setting that is already correct.
enum LocationAvailability {
  unknown,
  granted,

  /// The person, or the OS on their behalf, refused this app.
  denied,

  /// Permission is fine; no fix arrived this time. Transient.
  unavailable,
}

/// Keeps the stored location current as people move.
///
/// This used to refresh exactly once per app session, which made the deck as
/// stale as the session was long: someone who opened Flame at home, travelled
/// 40km and opened it again was still being matched from home. Distance is the
/// one filter a dating app cannot afford to be quietly wrong about.
///
/// Three rules, and the tension between them is the whole design:
///
/// 1. **Never nag.** A refusal is a decision, and it is respected for the rest
///    of the session — [refresh] does not ask again after a denial. That
///    property was the reason for once-per-session and it is preserved.
/// 2. **Never drain the battery.** GPS is not consulted more than once per
///    [minInterval], however often the app resumes.
/// 3. **Never push pointlessly.** A fix is only sent to the server when the
///    user has actually moved [movedKm], or when the stored point is older
///    than [maxAge]. Standing still costs one GPS read and no request.
class LocationRefresher {
  LocationRefresher({
    required this.getPosition,
    required this.push,
    this.resolvePlace,
    DateTime Function()? now,
    this.minInterval = const Duration(minutes: 5),
    this.maxAge = const Duration(minutes: 30),
    this.movedKm = 1.0,
  }) : _now = now ?? DateTime.now;

  /// The one thing this needs from LocationService, taken as a function rather
  /// than the service itself: LocationService is a singleton with a private
  /// constructor, so it cannot be subclassed for a test.
  final Future<LocationResult> Function() getPosition;

  final Future<bool> Function(
    double latitude,
    double longitude, {
    String? city,
    String? state,
    String? country,
  }) push;

  /// Turns coordinates into a city name, on the device. Optional: when it is
  /// absent or fails, the coordinates are still sent — the label is enrichment
  /// and must never cost someone their place in the deck.
  final Future<Place?> Function(double latitude, double longitude)? resolvePlace;

  final DateTime Function() _now;

  /// Floor on how often the GPS hardware is asked.
  final Duration minInterval;

  /// How long a stored point stays good while standing still. Re-sent after
  /// this even without movement, so a server-side point cannot silently rot.
  final Duration maxAge;

  /// How far someone must move before a new fix is worth sending.
  final double movedKm;

  LocationAvailability _availability = LocationAvailability.unknown;
  DateTime? _lastAsked;
  DateTime? _lastPushed;
  double? _lastLat;
  double? _lastLng;

  LocationAvailability get availability => _availability;

  /// Throttled, staleness-aware refresh. Safe to call on every screen open and
  /// every app resume — it decides for itself whether anything is due.
  Future<void> refresh() async {
    // A denial stands for the session. Re-prompting someone who said no, every
    // time they switch back to the app, is the definition of nagging.
    //
    // Only a denial, though. This used to test every failure, so one slow
    // indoor fix — the 15s timeout expiring — ended location updates for the
    // rest of the session and disabled the distance filter citing a permission
    // the person had actually granted. A failed fix gets to try again, still
    // behind the throttle below.
    if (_availability == LocationAvailability.denied) return;

    final asked = _lastAsked;
    if (asked != null && _now().difference(asked) < minInterval) return;

    await _read();
  }

  /// User-initiated refresh: ignores the throttle and retries after a denial.
  ///
  /// Someone who taps "update my location" has asked for exactly this, so the
  /// anti-nag rule does not apply — they are doing the asking.
  Future<bool> refreshNow() async {
    await _read(force: true);
    return _availability == LocationAvailability.granted;
  }

  Future<void> _read({bool force = false}) async {
    _lastAsked = _now();

    final result = await getPosition();
    final lat = result.latitude;
    final lng = result.longitude;

    if (!result.success || lat == null || lng == null) {
      // Recorded rather than swallowed: the filter sheet needs this to disable
      // the distance slider with a reason instead of offering a control that
      // cannot work.
      //
      // Which failure it was decides whether we ever look again. A refusal is
      // final until the person changes it; anything else is this attempt
      // failing, not the capability being gone.
      _availability = result.isRefusal
          ? LocationAvailability.denied
          : LocationAvailability.unavailable;
      return;
    }

    _availability = LocationAvailability.granted;

    if (!force && !_isWorthPushing(lat, lng)) return;

    // Resolved before the push so the name travels with the coordinates, in
    // one request. A null here is ordinary — offline, or a coordinate the
    // platform has no name for — and the server keeps whatever it already had.
    Place? place;
    if (resolvePlace != null) {
      place = await resolvePlace!(lat, lng);
    }

    // A failed PATCH changes nothing the user can see: the previously stored
    // point stands, and the next refresh tries again. Only a success updates
    // the local record, so a failure does not convince us we are current.
    if (await push(
      lat,
      lng,
      city: place?.city,
      state: place?.state,
      country: place?.country,
    )) {
      _lastPushed = _now();
      _lastLat = lat;
      _lastLng = lng;
    }
  }

  bool _isWorthPushing(double lat, double lng) {
    final pushedAt = _lastPushed;
    final lastLat = _lastLat;
    final lastLng = _lastLng;

    // Nothing sent this session yet — the stored point may be from a previous
    // launch, in another city.
    if (pushedAt == null || lastLat == null || lastLng == null) return true;

    if (_now().difference(pushedAt) >= maxAge) return true;

    return distanceKm(lastLat, lastLng, lat, lng) >= movedKm;
  }
}

final locationRefresherProvider = Provider<LocationRefresher>((ref) {
  final resolver = PlaceResolver();
  return LocationRefresher(
    getPosition: LocationService().getCurrentPosition,
    resolvePlace: resolver.resolve,
    push: (lat, lng, {city, state, country}) =>
        ref.read(currentUserProvider.notifier).updateLocation(
              lat,
              lng,
              city: city,
              state: state,
              country: country,
            ),
  );
});
