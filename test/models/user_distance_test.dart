import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';

Map<String, dynamic> _json(Object? distance) => {
      'id': 'u1', 'name': 'A', 'photos': <dynamic>[],
      if (distance != null) 'distance': distance,
    };

void main() {
  test('a missing distance is unknown, not zero', () {
    expect(User.fromJson(_json(null)).distance, isNull);
  });

  test('an explicit null is unknown', () {
    expect(User.fromJson({..._json(null), 'distance': null}).distance, isNull);
  });

  test('zero is treated as unknown', () {
    // A server that has not deployed the real computation still sends 0, and a
    // genuine 0 km means standing on the exact same point.
    expect(User.fromJson(_json(0)).distance, isNull);
  });

  test('a real distance survives, int or double', () {
    expect(User.fromJson(_json(12.5)).distance, 12.5);
    expect(User.fromJson(_json(12)).distance, 12.0);
  });
}
