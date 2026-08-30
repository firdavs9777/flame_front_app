import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';
import 'package:flame/services/user_service.dart';

void main() {
  group('buildUpdateProfileBody', () {
    // A social signup has no /auth/register call to carry its consent, so this
    // PATCH is the only place it can be recorded. Until it was, those accounts
    // reached a finished state having agreed to nothing.
    test('carries the social path\'s consent when it was given', () {
      final body = buildUpdateProfileBody(name: 'Ann', termsAccepted: true);
      expect(body['termsAccepted'], true);
    });

    test('says nothing about consent when none was given', () {
      // An ordinary profile edit must not restate consent, and there is no such
      // thing as withdrawing it by editing a bio — so false is silence, not
      // `termsAccepted: false`.
      expect(buildUpdateProfileBody(bio: 'hi').containsKey('termsAccepted'),
          isFalse);
      expect(
          buildUpdateProfileBody(bio: 'hi', termsAccepted: false)
              .containsKey('termsAccepted'),
          isFalse);
    });

    test('never sends a client-chosen acceptance time', () {
      // The server stamps the date and the version. A timestamp from the client
      // is a claim about consent, not a record of it.
      final body = buildUpdateProfileBody(termsAccepted: true);
      expect(body.containsKey('termsAcceptedAt'), isFalse);
      expect(body.containsKey('termsVersion'), isFalse);
    });

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

    test('writes gender in camelCase when given', () {
      final body = buildUpdateProfileBody(gender: Gender.female);
      expect(body['gender'], 'female');
    });

    test('gender needs no snake_case twin — the PATCH schema names it gender', () {
      final body = buildUpdateProfileBody(gender: Gender.male);
      expect(body['gender'], 'male');
      expect(body.containsKey('gender_identity'), isFalse);
    });

    test('omits gender when null — a profile edit must not reset it', () {
      final body = buildUpdateProfileBody(name: 'Ann');
      expect(body.containsKey('gender'), isFalse);
    });
  });
}
