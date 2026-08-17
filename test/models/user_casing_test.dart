import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';

// Mirrors the live prod GET /users/me shape (camelCase).
Map<String, dynamic> _camelPayload() => {
      'id': 'u1',
      'email': 'a@b.com',
      'name': 'Ann',
      'age': 27,
      'bio': 'hi',
      'photos': <dynamic>[],
      'location': null,
      'interests': <dynamic>[],
      'gender': 'female',
      'lookingFor': 'male',
      'isOnline': true,
      'isVerified': true,
      'isPremium': true,
      'premiumExpiresAt': '2027-01-01T00:00:00.000Z',
      'lastActive': '2026-07-20T10:00:00.000Z',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'preferences': {
        'minAge': 21,
        'maxAge': 40,
        'maxDistance': 25,
        'showDistance': false,
        'showOnlineStatus': false,
      },
    };

// Mirrors the /discover shape (snake_case).
Map<String, dynamic> _snakePayload() => {
      'id': 'u2',
      'name': 'Bo',
      'age': 30,
      'bio': 'yo',
      'photos': <dynamic>[],
      'interests': <dynamic>[],
      'gender': 'male',
      'looking_for': 'female',
      'is_online': true,
      'is_verified': true,
      'is_premium': true,
      'premium_expires_at': '2027-01-01T00:00:00.000Z',
      'last_active': '2026-07-20T10:00:00.000Z',
      'created_at': '2026-01-01T00:00:00.000Z',
      'preferences': {
        'min_age': 22,
        'max_age': 45,
        'max_distance': 30,
        'show_distance': false,
        'show_online_status': false,
      },
    };

void main() {
  group('User.fromJson camelCase (/users/me, /auth/*)', () {
    test('parses lookingFor / isOnline / isVerified / dates', () {
      final u = User.fromJson(_camelPayload());
      expect(u.lookingFor, Gender.male);
      expect(u.isOnline, isTrue);
      expect(u.isVerified, isTrue);
      expect(u.createdAt, isNotNull);
      expect(u.lastActive.year, 2026);
    });

    // isPremium / premiumExpiresAt were the only pair in the constructor with
    // no camelCase fallback, while every neighbouring field had one. That gap
    // is not visible from either side on its own: the model test seeded
    // snake_case and passed, so a camelCase server would have parsed the pair
    // as (false, null) and the premium badge would have stayed hidden for a
    // paying user with no failing test anywhere.
    test('parses camelCase premium fields', () {
      final u = User.fromJson(_camelPayload());
      expect(u.isPremium, isTrue);
      expect(u.premiumExpiresAt, isNotNull);
      expect(u.premiumExpiresAt!.year, 2027);
      expect(
        u.isPremiumActive,
        isTrue,
        reason:
            'a paying user whose entitlement arrives in camelCase must not '
            'read as lapsed',
      );
    });

    test('parses camelCase preferences', () {
      final u = User.fromJson(_camelPayload());
      expect(u.minAgePreference, 21);
      expect(u.maxAgePreference, 40);
      expect(u.maxDistancePreference, 25);
      expect(u.showDistance, isFalse);
      expect(u.showOnlineStatus, isFalse);
    });
  });

  group('User.fromJson snake_case (/discover) still works', () {
    test('parses looking_for / is_online and snake preferences', () {
      final u = User.fromJson(_snakePayload());
      expect(u.lookingFor, Gender.female);
      expect(u.isOnline, isTrue);
      expect(u.minAgePreference, 22);
      expect(u.maxDistancePreference, 30);
      expect(u.showOnlineStatus, isFalse);
    });

    test('still parses snake_case premium fields', () {
      final u = User.fromJson(_snakePayload());
      expect(u.isPremium, isTrue);
      expect(u.premiumExpiresAt!.year, 2027);
    });
  });
}
