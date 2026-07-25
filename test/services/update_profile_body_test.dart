import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';
import 'package:flame/services/user_service.dart';

void main() {
  group('buildUpdateProfileBody', () {
    test('omits null fields', () {
      final body = buildUpdateProfileBody(name: 'Ann');
      expect(body.keys, ['name']);
      expect(body['name'], 'Ann');
    });

    test('writes lookingFor in camelCase (backend read key)', () {
      final body = buildUpdateProfileBody(lookingFor: Gender.male);
      expect(body['lookingFor'], 'male');
    });

    test('also includes snake_case looking_for for forward-compat', () {
      final body = buildUpdateProfileBody(lookingFor: Gender.female);
      expect(body['looking_for'], 'female');
    });

    test('passes through name/bio/interests/age', () {
      final body = buildUpdateProfileBody(
        name: 'Ann',
        bio: 'hi',
        interests: ['a', 'b'],
        age: 29,
      );
      expect(body['name'], 'Ann');
      expect(body['bio'], 'hi');
      expect(body['interests'], ['a', 'b']);
      expect(body['age'], 29);
    });
  });
}
