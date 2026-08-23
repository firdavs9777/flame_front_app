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
  test('fromJson reads locale when present', () {
    final json = _baseJson()..['locale'] = 'es';
    final user = User.fromJson(json);
    expect(user.locale, 'es');
  });

  test('fromJson reads pt-BR style country-coded tag', () {
    final json = _baseJson()..['locale'] = 'pt-BR';
    final user = User.fromJson(json);
    expect(user.locale, 'pt-BR');
  });

  test('fromJson sets preferredLanguage to null when field absent', () {
    final user = User.fromJson(_baseJson());
    expect(user.locale, isNull);
  });

  test('toJson includes locale', () {
    final user = User.fromJson(_baseJson()..['locale'] = 'fr');
    expect(user.toJson()['locale'], 'fr');
  });

  test('copyWith updates preferredLanguage', () {
    final user = User.fromJson(_baseJson());
    final updated = user.copyWith(locale: 'de');
    expect(updated.locale, 'de');
  });
}
