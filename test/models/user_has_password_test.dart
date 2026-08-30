import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';

// A social signup has no password, so the delete-account dialog cannot demand
// one — doing so put the account deletion Google Play requires out of reach for
// every Google user. The self-view payload carries `hasPassword` so the dialog
// knows which of the two flows to show.

void main() {
  group('User.hasPassword', () {
    test('reads camelCase hasPassword from the self-view payload', () {
      final user = User.fromJson({'id': 'u1', 'name': 'Ada', 'hasPassword': true});
      expect(user.hasPassword, isTrue);
    });

    test('reads snake_case has_password too', () {
      final user = User.fromJson({'id': 'u1', 'name': 'Ada', 'has_password': false});
      expect(user.hasPassword, isFalse);
    });

    test('defaults to true when the field is absent', () {
      // An older API version, or a deploy window. Defaulting to true keeps the
      // password prompt for password accounts; the cost of guessing wrong is a
      // prompt a social user can dismiss, not a lockout.
      final user = User.fromJson({'id': 'u1', 'name': 'Ada'});
      expect(user.hasPassword, isTrue);
    });
  });
}
