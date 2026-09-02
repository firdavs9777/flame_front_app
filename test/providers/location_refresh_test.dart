import 'package:flutter_test/flutter_test.dart';
import 'package:flame/providers/location_provider.dart';
import 'package:flame/services/location_service.dart';

/// A stand-in for LocationService.getCurrentPosition, which cannot be faked by
/// subclassing — the service is a singleton with a private constructor.
class _Position {
  _Position({this.ok = true, this.lat = 1.5, this.lng = 2.5});

  bool ok;
  double lat;
  double lng;
  int calls = 0;

  Future<LocationResult> call() async {
    calls++;
    if (!ok) return LocationResult.failure('denied');
    return LocationResult.successAt(lat, lng);
  }
}

/// A clock the test moves by hand, so staleness is exercised without waiting.
class _Clock {
  DateTime value = DateTime(2026, 9, 2, 12, 0);
  DateTime call() => value;
  void advance(Duration d) => value = value.add(d);
}

void main() {
  test('the first refresh pushes, and an immediate second one does not',
      () async {
    final source = _Position();
    final clock = _Clock();
    final pushed = <List<double>>[];
    final r = LocationRefresher(
      getPosition: source.call,
      push: (lat, lng) async {
        pushed.add([lat, lng]);
        return true;
      },
      now: clock.call,
    );

    await r.refresh();
    await r.refresh();
    await r.refresh();

    // The throttle stops the GPS being asked on every screen open.
    expect(source.calls, 1);
    expect(pushed, [
      [1.5, 2.5]
    ]);
    expect(r.availability, LocationAvailability.granted);
  });

  test('a refusal is recorded and never retried in the same session', () async {
    // The anti-nag rule the once-per-session design existed to provide. It
    // survives: someone who said no is not asked again on every resume.
    final source = _Position(ok: false);
    final clock = _Clock();
    var pushes = 0;
    final r = LocationRefresher(
      getPosition: source.call,
      push: (_, __) async {
        pushes++;
        return true;
      },
      now: clock.call,
    );

    await r.refresh();
    clock.advance(const Duration(hours: 2));
    await r.refresh();

    expect(source.calls, 1, reason: 'a denial must not be re-prompted');
    expect(pushes, 0);
    expect(r.availability, LocationAvailability.denied);
  });

  test('standing still costs a GPS read but no request', () async {
    // The old design refreshed once and stopped. The new one may look again —
    // it must not send a pointless PATCH when nothing has changed.
    final source = _Position();
    final clock = _Clock();
    var pushes = 0;
    final r = LocationRefresher(
      getPosition: source.call,
      push: (_, __) async {
        pushes++;
        return true;
      },
      now: clock.call,
    );

    await r.refresh();
    clock.advance(const Duration(minutes: 6));
    await r.refresh();

    expect(source.calls, 2, reason: 'the throttle window has passed');
    expect(pushes, 1, reason: 'but they have not moved');
  });

  test('moving far enough pushes again — the bug this fixes', () async {
    // Someone opens Flame at home, travels, and opens it again. Under
    // once-per-session they were still being matched from home.
    final source = _Position(lat: 51.5, lng: -0.12);
    final clock = _Clock();
    final pushed = <List<double>>[];
    final r = LocationRefresher(
      getPosition: source.call,
      push: (lat, lng) async {
        pushed.add([lat, lng]);
        return true;
      },
      now: clock.call,
    );

    await r.refresh();

    clock.advance(const Duration(minutes: 6));
    source.lat = 51.75; // ~28 km north
    await r.refresh();

    expect(pushed, hasLength(2));
    expect(pushed.last, [51.75, -0.12]);
  });

  test('a small move is not worth a request', () async {
    final source = _Position(lat: 51.5, lng: -0.12);
    final clock = _Clock();
    var pushes = 0;
    final r = LocationRefresher(
      getPosition: source.call,
      push: (_, __) async {
        pushes++;
        return true;
      },
      now: clock.call,
    );

    await r.refresh();
    clock.advance(const Duration(minutes: 6));
    source.lat = 51.502; // ~200 m — walking to the shop
    await r.refresh();

    expect(pushes, 1);
  });

  test('a stored point is re-sent once it is old, even standing still',
      () async {
    // So a server-side location cannot silently rot while someone sits at
    // home with the app open all afternoon.
    final source = _Position();
    final clock = _Clock();
    var pushes = 0;
    final r = LocationRefresher(
      getPosition: source.call,
      push: (_, __) async {
        pushes++;
        return true;
      },
      now: clock.call,
    );

    await r.refresh();
    clock.advance(const Duration(minutes: 31));
    await r.refresh();

    expect(pushes, 2);
  });

  test('a failed push is not remembered as current', () async {
    // Otherwise one flaky request convinces the refresher it is up to date,
    // and the stale point stays stale until the user moves a kilometre.
    final source = _Position();
    final clock = _Clock();
    var attempts = 0;
    final r = LocationRefresher(
      getPosition: source.call,
      push: (_, __) async {
        attempts++;
        return false;
      },
      now: clock.call,
    );

    await r.refresh();
    clock.advance(const Duration(minutes: 6));
    await r.refresh();

    expect(attempts, 2, reason: 'the second refresh must retry, not skip');
  });

  group('refreshNow — the user asked', () {
    test('ignores the throttle', () async {
      final source = _Position();
      final clock = _Clock();
      final r = LocationRefresher(
        getPosition: source.call,
        push: (_, __) async => true,
        now: clock.call,
      );

      await r.refresh();
      final ok = await r.refreshNow();

      expect(source.calls, 2, reason: 'no waiting when the user taps refresh');
      expect(ok, isTrue);
    });

    test('pushes even when they have not moved', () async {
      // Tapping "update my location" and having nothing happen reads as broken,
      // even when the stored point is already correct.
      final source = _Position();
      final clock = _Clock();
      var pushes = 0;
      final r = LocationRefresher(
        getPosition: source.call,
        push: (_, __) async {
          pushes++;
          return true;
        },
        now: clock.call,
      );

      await r.refresh();
      await r.refreshNow();

      expect(pushes, 2);
    });

    test('retries after a denial, because this time they asked', () async {
      final source = _Position(ok: false);
      final clock = _Clock();
      final r = LocationRefresher(
        getPosition: source.call,
        push: (_, __) async => true,
        now: clock.call,
      );

      await r.refresh();
      expect(r.availability, LocationAvailability.denied);

      source.ok = true;
      final ok = await r.refreshNow();

      expect(ok, isTrue);
      expect(r.availability, LocationAvailability.granted);
    });

    test('reports failure when the fix cannot be had', () async {
      final r = LocationRefresher(
        getPosition: _Position(ok: false).call,
        push: (_, __) async => true,
      );

      expect(await r.refreshNow(), isFalse);
    });
  });
}
