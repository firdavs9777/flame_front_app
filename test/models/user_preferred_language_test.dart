import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';

Map<String, dynamic> _baseJson() => {
      'id': '1',
      'name': 'Alice',
      'age': 30,
      'bio': '',
      'photos': <String>[],
      'location': '',
      'interests': <String>[],
      'gender': 'female',
      'looking_for': 'male',
    };

void main() {
  test('fromJson reads preferred_language when present', () {
    final json = _baseJson()..['preferred_language'] = 'es';
    final user = User.fromJson(json);
    expect(user.preferredLanguage, 'es');
  });

  test('fromJson reads pt-BR style country-coded tag', () {
    final json = _baseJson()..['preferred_language'] = 'pt-BR';
    final user = User.fromJson(json);
    expect(user.preferredLanguage, 'pt-BR');
  });

  test('fromJson sets preferredLanguage to null when field absent', () {
    final user = User.fromJson(_baseJson());
    expect(user.preferredLanguage, isNull);
  });

  test('toJson includes preferred_language', () {
    final user = User.fromJson(_baseJson()..['preferred_language'] = 'fr');
    expect(user.toJson()['preferred_language'], 'fr');
  });

  test('copyWith updates preferredLanguage', () {
    final user = User.fromJson(_baseJson());
    final updated = user.copyWith(preferredLanguage: 'de');
    expect(updated.preferredLanguage, 'de');
  });
}
