import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as geo;

/// A human-readable place, as far as it could be determined.
///
/// Every field is nullable and independently so: reverse geocoding is a
/// best-effort lookup, and plenty of real coordinates resolve to a country and
/// nothing else — at sea, in sparsely mapped regions, or simply where the
/// platform's data is thin.
@immutable
class Place {
  const Place({this.city, this.state, this.country});

  final String? city;
  final String? state;
  final String? country;

  bool get isEmpty => city == null && state == null && country == null;

  @override
  bool operator ==(Object other) =>
      other is Place &&
      other.city == city &&
      other.state == state &&
      other.country == country;

  @override
  int get hashCode => Object.hash(city, state, country);

  @override
  String toString() => 'Place($city, $state, $country)';
}

/// Turns coordinates into a city name, on the device.
///
/// **On the device, deliberately.** The alternative — reverse-geocoding on the
/// server when a location is PATCHed — would mean sending every user's precise
/// coordinates to a third-party geocoding service, on every update, forever.
/// The phone already has a platform API that answers locally, so the coarse
/// answer can be produced without anyone else learning the precise question.
///
/// It also costs no API key, no quota, and no server configuration.
class PlaceResolver {
  PlaceResolver({
    Future<List<geo.Placemark>> Function(double, double)? lookup,
  }) : _lookup = lookup ?? _platformLookup;

  final Future<List<geo.Placemark>> Function(double, double) _lookup;

  /// One instance, created lazily. In geocoding 5.x this is an object with an
  /// instance method rather than the top-level function earlier versions had,
  /// and building a new one per lookup would re-create the platform channel
  /// wrapper on every location update.
  static geo.Geocoding? _geocoding;

  static Future<List<geo.Placemark>> _platformLookup(double lat, double lng) {
    final geocoding = _geocoding ??= geo.Geocoding();
    return geocoding.placemarkFromCoordinates(lat, lng);
  }

  /// Best-effort. Returns null rather than throwing when the lookup fails,
  /// because a location update must still happen with coordinates alone — the
  /// city is a label, and losing it must never cost the user their place in
  /// the deck.
  Future<Place?> resolve(double latitude, double longitude) async {
    try {
      final marks = await _lookup(latitude, longitude);
      if (marks.isEmpty) return null;

      final m = marks.first;

      // locality first, then the coarser fallbacks: plenty of coordinates have
      // no locality but do sit in a named sub-administrative area, and "Kent"
      // is a better answer than nothing.
      final city = _clean(m.locality) ??
          _clean(m.subAdministrativeArea) ??
          _clean(m.subLocality);
      final state = _clean(m.administrativeArea);
      final country = _clean(m.country);

      final place = Place(city: city, state: state, country: country);
      return place.isEmpty ? null : place;
    } catch (error) {
      debugPrint('PlaceResolver: reverse geocode failed — $error');
      return null;
    }
  }

  /// Empty and whitespace-only names are absent, not values — the platform
  /// returns '' rather than null for fields it has no answer for.
  static String? _clean(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
