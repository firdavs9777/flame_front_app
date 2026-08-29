import 'package:flutter_test/flutter_test.dart';
import 'package:flame/services/location_service.dart';
import 'package:flame/screens/auth/registration/location_gate.dart';

// The backend calls a profile complete only when photos AND a non-empty
// interest AND location coordinates are all present (flame_backend
// app/core/profile.py). Registration sends coordinates with /auth/register, but
// a social signup is created without them and the completion flow never
// established any — it relied, without saying so, on LocationRefresher pushing
// a point later from the Discover screen. That is fire-and-forget enrichment:
// it no-ops after one attempt per session, ignores a failed PATCH by design,
// and never runs at all if the user denies the prompt or the app dies first.
// Any of those returns the user to this wizard on next launch.
//
// So the flow establishes its own coordinates, and a failure is reported rather
// than passed off as a completed profile.

class _Source {
  LocationResult result = LocationResult.successAt(52.5, 13.4);
  bool pushSucceeds = true;
  final List<List<double>> pushed = [];
  var positionCalls = 0;

  Future<LocationResult> getPosition() async {
    positionCalls++;
    return result;
  }

  Future<bool> push(double latitude, double longitude) async {
    pushed.add([latitude, longitude]);
    return pushSucceeds;
  }
}

void main() {
  group('LocationGate.establish', () {
    test('pushes the resolved coordinates', () async {
      final source = _Source();

      final result = await const LocationGate().establish(
        getPosition: source.getPosition,
        push: source.push,
      );

      expect(result.ok, isTrue);
      expect(source.pushed, [
        [52.5, 13.4]
      ]);
    });

    test('reports a refused prompt, and pushes nothing', () async {
      final source = _Source()..result = LocationResult.failure('denied');

      final result = await const LocationGate().establish(
        getPosition: source.getPosition,
        push: source.push,
      );

      expect(result.ok, isFalse);
      expect(result.failure, LocationGateFailure.position);
      expect(result.error, 'denied');
      expect(source.pushed, isEmpty);
    });

    test('reports a failed push rather than reporting a complete profile',
        () async {
      final source = _Source()..pushSucceeds = false;

      final result = await const LocationGate().establish(
        getPosition: source.getPosition,
        push: source.push,
      );

      expect(result.ok, isFalse);
      expect(result.failure, LocationGateFailure.push);
    });

    test('treats a success carrying no coordinates as a failure', () async {
      // LocationResult.success(position) can report success with a Position
      // this layer cannot read; guarding the nulls keeps a `!` off the caller.
      final source = _Source()..result = LocationResult.failure('no fix');

      final result = await const LocationGate().establish(
        getPosition: source.getPosition,
        push: source.push,
      );

      expect(result.ok, isFalse);
      expect(source.pushed, isEmpty);
    });
  });
}
