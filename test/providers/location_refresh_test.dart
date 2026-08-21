import 'package:flutter_test/flutter_test.dart';
import 'package:flame/providers/location_provider.dart';
import 'package:flame/services/location_service.dart';

/// A stand-in for LocationService.getCurrentPosition, which cannot be faked by
/// subclassing — the service is a singleton with a private constructor.
class _Position {
  _Position({this.ok = true});
  final bool ok;
  int calls = 0;

  Future<LocationResult> call() async {
    calls++;
    if (!ok) return LocationResult.failure('denied');
    return LocationResult.successAt(1.5, 2.5);
  }
}

void main() {
  test('a successful refresh pushes the coordinates once per session', () async {
    final source = _Position();
    final pushed = <List<double>>[];
    final r = LocationRefresher(
      getPosition: source.call,
      push: (lat, lng) async {
        pushed.add([lat, lng]);
        return true;
      },
    );

    await r.refreshOnce();
    await r.refreshOnce();
    await r.refreshOnce();

    expect(source.calls, 1, reason: 'once per session, not once per open');
    expect(pushed, [[1.5, 2.5]]);
    expect(r.availability, LocationAvailability.granted);
  });

  test('a refusal is recorded and not retried', () async {
    final source = _Position(ok: false);
    var pushes = 0;
    final r = LocationRefresher(
      getPosition: source.call,
      push: (_, __) async {
        pushes++;
        return true;
      },
    );

    await r.refreshOnce();
    await r.refreshOnce();

    expect(source.calls, 1, reason: 'asking on every open is nagging');
    expect(pushes, 0);
    expect(r.availability, LocationAvailability.denied,
        reason: 'the filter sheet disables the distance slider on this');
  });

  test('a failed push still counts the permission as granted', () async {
    final r = LocationRefresher(
      getPosition: _Position().call,
      push: (_, __) async => false,
    );

    await r.refreshOnce();

    expect(r.availability, LocationAvailability.granted,
        reason: 'the position was obtained; only the PATCH failed');
  });

  test('availability starts unknown', () {
    final r = LocationRefresher(getPosition: _Position().call, push: (_, __) async => true);

    expect(r.availability, LocationAvailability.unknown);
  });
}
