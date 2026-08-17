// isPremiumActive is money-relevant: it had drifted into two call sites
// (swipe_provider.dart's undo gate and my_profile_screen.dart's header)
// each re-deriving "isPremium && (premiumExpiresAt is null or in the
// future)" independently. It now lives once, on the model, and both sites
// delegate to it. These tests pin its four cases directly so a future edit
// to the getter can't silently change behaviour at either call site without
// this file catching it first.
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';

User _user({required bool isPremium, DateTime? premiumExpiresAt}) {
  return User(
    id: 'u1',
    name: 'Ann',
    age: 27,
    bio: '',
    photos: const [],
    location: 'Unknown',
    interests: const [],
    gender: Gender.female,
    lookingFor: Gender.male,
    lastActive: DateTime.now(),
    isPremium: isPremium,
    premiumExpiresAt: premiumExpiresAt,
  );
}

void main() {
  group('User.isPremiumActive', () {
    test('not premium at all is never active', () {
      final u = _user(isPremium: false);
      expect(u.isPremiumActive, isFalse);
    });

    test('premium with no expiry is active', () {
      final u = _user(isPremium: true, premiumExpiresAt: null);
      expect(u.isPremiumActive, isTrue);
    });

    test('premium expiring in the future is active', () {
      final u = _user(
        isPremium: true,
        premiumExpiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      expect(u.isPremiumActive, isTrue);
    });

    test('premium that already expired is not active', () {
      final u = _user(
        isPremium: true,
        premiumExpiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(
        u.isPremiumActive,
        isFalse,
        reason:
            'a lapsed subscription reading as active is the one failure '
            'here that costs real money to get wrong',
      );
    });

    test('a non-premium user with a future expiresAt is still not active', () {
      // isPremium is the gate; a stale expiry field left over from a prior
      // subscription must not resurrect it.
      final u = _user(
        isPremium: false,
        premiumExpiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      expect(u.isPremiumActive, isFalse);
    });
  });
}
