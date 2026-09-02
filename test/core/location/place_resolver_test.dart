import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';

import 'package:flame/core/location/place_resolver.dart';

Placemark _mark({
  String? locality,
  String? subAdministrativeArea,
  String? subLocality,
  String? administrativeArea,
  String? country,
}) =>
    Placemark(
      locality: locality,
      subAdministrativeArea: subAdministrativeArea,
      subLocality: subLocality,
      administrativeArea: administrativeArea,
      country: country,
    );

PlaceResolver _resolver(Future<List<Placemark>> Function(double, double) f) =>
    PlaceResolver(lookup: f);

void main() {
  test('reads the city, state and country from the first placemark', () async {
    final r = _resolver((_, __) async => [
          _mark(
            locality: 'London',
            administrativeArea: 'England',
            country: 'United Kingdom',
          ),
        ]);

    final place = await r.resolve(51.5, -0.12);

    expect(place, isNotNull);
    expect(place!.city, 'London');
    expect(place.state, 'England');
    expect(place.country, 'United Kingdom');
  });

  test('falls back through the coarser fields when there is no locality',
      () async {
    // Real coordinates often have no locality but do sit in a named area, and
    // "Kent" is a better answer than nothing at all.
    final r = _resolver((_, __) async => [
          _mark(subAdministrativeArea: 'Kent', country: 'United Kingdom'),
        ]);

    expect((await r.resolve(51.2, 0.5))!.city, 'Kent');
  });

  test('treats the empty strings the platform returns as absent', () async {
    // The platform APIs return '' rather than null for fields they have no
    // answer for, which would otherwise render as ", " on a profile.
    final r = _resolver((_, __) async => [
          _mark(locality: '  ', administrativeArea: '', country: 'Japan'),
        ]);

    final place = await r.resolve(35.6, 139.7);

    expect(place!.city, isNull);
    expect(place.state, isNull);
    expect(place.country, 'Japan');
  });

  test('returns null when nothing at all could be named', () async {
    final r = _resolver((_, __) async => [_mark()]);
    expect(await r.resolve(0, 0), isNull);
  });

  test('returns null for an empty result rather than throwing', () async {
    final r = _resolver((_, __) async => []);
    expect(await r.resolve(0, 0), isNull);
  });

  test('a failed lookup is null, never an exception', () async {
    // This runs inside a location update. If it threw, a user offline — or on
    // a platform with no geocoder — would lose the coordinate update too, and
    // with it their place in the deck. The label is worth strictly less than
    // the location.
    final r = _resolver((_, __) async => throw Exception('no geocoder'));

    expect(await r.resolve(51.5, -0.12), isNull);
  });

  test('passes the coordinates through unchanged', () async {
    // Latitude and longitude are trivially transposable, and a swap puts the
    // user on another continent with no error to show for it.
    final seen = <double>[];
    final r = _resolver((lat, lng) async {
      seen.addAll([lat, lng]);
      return [_mark(locality: 'X')];
    });

    await r.resolve(51.5, -0.12);

    expect(seen, [51.5, -0.12]);
  });

  test('Place equality is by value, so an unchanged city is not a change', () {
    expect(
      const Place(city: 'A', state: 'B', country: 'C'),
      const Place(city: 'A', state: 'B', country: 'C'),
    );
    expect(
      const Place(city: 'A'),
      isNot(const Place(city: 'B')),
    );
    expect(const Place().isEmpty, isTrue);
    expect(const Place(country: 'C').isEmpty, isFalse);
  });
}
