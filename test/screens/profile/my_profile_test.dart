// isVerified, isPremium and premiumExpiresAt are parsed by User and shown
// nowhere on the profile screen. This test drives the header rendering
// directly off an overridden currentUserProvider, following
// conversations_realtime_test.dart's _Seeded pattern: a notifier subclass
// whose constructor seeds state, so no real network is ever touched.
//
// The premium-expiry case is the one that matters most: a lapsed
// subscription rendering as active is the one failure here that costs real
// money to get wrong.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/navigation/app_routes.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/user_provider.dart';
import 'package:flame/screens/profile/my_profile_screen.dart';
import 'package:flame/services/user_service.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/l10n/gen/app_localizations.dart';

// MyProfileScreen calls loadUser() from initState's post-frame callback.
// Overriding getCurrentUser here — rather than leaving the real UserService
// in place — means that call resolves to the same seeded user instead of
// hitting the network and flipping the screen to an error state mid-test.
class _FakeUserService extends UserService {
  _FakeUserService(this._user);
  final User _user;

  @override
  Future<ServiceResult<User>> getCurrentUser() async {
    return ServiceResult.success(_user);
  }
}

User _user({
  bool isVerified = false,
  bool isPremium = false,
  DateTime? premiumExpiresAt,
  double maxDistance = 25,
  List<String> interests = const <String>[],
  List<String> photos = const <String>[],
}) {
  return User.fromJson({
    'id': 'u1',
    'name': 'Alex',
    'age': 28,
    'bio': 'Hello there',
    'interests': interests,
    'gender': 'male',
    'looking_for': 'female',
    'photos': photos,
    'preferences': {'max_distance': maxDistance},
    'is_verified': isVerified,
    'is_premium': isPremium,
    if (premiumExpiresAt != null)
      'premium_expires_at': premiumExpiresAt.toIso8601String(),
  });
}

/// Every route the screen pushes, so a tap can be checked for where it went
/// rather than only for having gone somewhere.
final List<RouteSettings> _pushed = [];

Widget _host(User user, {ThemeData? theme, Locale locale = const Locale('en')}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => CurrentUserNotifier(_FakeUserService(user))..setUser(user),
      ),
    ],
    child: MaterialApp(
      theme: theme,
      // The settings gear's tooltip reads from the ARBs, so the screen needs
      // localizations to build.
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateRoute: (settings) {
        if (settings.name != null) _pushed.add(settings);
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const Placeholder(),
        );
      },
      home: const MyProfileScreen(),
    ),
  );
}

void main() {
  _phase4Tests();

  group('verification badge', () {
    testWidgets('a verified user shows a verification badge', (tester) async {
      await tester.pumpWidget(_host(_user(isVerified: true)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verified_badge')), findsOneWidget);
    });

    testWidgets('an unverified user shows no verification badge', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_user(isVerified: false)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verified_badge')), findsNothing);
    });
  });

  group('premium state', () {
    testWidgets('a premium user with no expiry shows premium state', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_user(isPremium: true)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('premium_badge')), findsOneWidget);
    });

    testWidgets(
      'a non-premium user shows nothing — not a greyed-out badge',
      (tester) async {
        await tester.pumpWidget(_host(_user(isPremium: false)));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('premium_badge')), findsNothing);
      },
    );

    testWidgets(
      'a premium user whose premiumExpiresAt is in the past does not show '
      'as premium',
      (tester) async {
        await tester.pumpWidget(
          _host(
            _user(
              isPremium: true,
              premiumExpiresAt: DateTime.now().subtract(
                const Duration(days: 1),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('premium_badge')),
          findsNothing,
          reason:
              'an expired subscription rendering as active is the one '
              'failure here that costs real money to get wrong',
        );
      },
    );

    testWidgets(
      'a premium user whose premiumExpiresAt is in the future shows as '
      'premium',
      (tester) async {
        await tester.pumpWidget(
          _host(
            _user(
              isPremium: true,
              premiumExpiresAt: DateTime.now().add(const Duration(days: 30)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('premium_badge')), findsOneWidget);
      },
    );
  });

  // This screen rendered `maxDistancePreference.toInt()`, truncating, while
  // the editor one tap away deliberately stopped rounding. A stored 24.6 read
  // as "24 km" here and "24.6" there — two answers to the same stored number,
  // and the truncated one is the one the user is more likely to believe.
  group('max distance formatting', () {
    testWidgets('a fractional stored distance is not truncated', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_user(maxDistance: 24.6)));
      await tester.pumpAndSettle();

      expect(find.text('24.6 km'), findsOneWidget);
      expect(
        find.text('24 km'),
        findsNothing,
        reason: 'the profile and the editor must agree on the same value',
      );
    });

    testWidgets('a whole stored distance prints without a .0', (tester) async {
      await tester.pumpWidget(_host(_user(maxDistance: 25)));
      await tester.pumpAndSettle();

      expect(find.text('25 km'), findsOneWidget);
    });
  });

  // Task 5 exists so these screens are dark-mode-correct; a header addition
  // with no dark coverage would leave that claim untested for the screen it
  // most applies to. A smoke test, not a golden — goldens on themed screens
  // break on every palette change and get regenerated without being read.
  group('renders without throwing', () {
    final themes = {'light': AppTheme.lightTheme, 'dark': AppTheme.darkTheme};

    for (final entry in themes.entries) {
      testWidgets('in ${entry.key} theme', (tester) async {
        await tester.pumpWidget(
          _host(
            _user(
              isVerified: true,
              isPremium: true,
              premiumExpiresAt: DateTime.now().add(const Duration(days: 30)),
            ),
            theme: entry.value,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('verified_badge')), findsOneWidget);
        expect(find.byKey(const Key('premium_badge')), findsOneWidget);
      });
    }
  });
}

// The profile screen showed things the user owns and gave no way to act on
// them: the photo grid had no onTap at all, and the Photos and Interests
// blocks never mentioned that Edit Profile is where you change them. The
// interest chips had a subtler problem — they rendered the stored token, so
// every interest read English in all 32 locales while the translations for
// them sat unused in the ARBs.
void _phase4Tests() {
  const photos = ['https://x/1.jpg', 'https://x/2.jpg'];

  setUp(_pushed.clear);

  group('photo tap targets', () {
    testWidgets('tapping a photo opens the viewer on that photo', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_user(photos: photos)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('profile_photo_1')));
      await tester.pumpAndSettle();

      expect(_pushed.single.name, AppRoutes.mediaViewer,
          reason: 'the tile used to have no onTap at all');
      final args = _pushed.single.arguments as MediaViewerArgs;
      expect(args.images, photos, reason: 'you can swipe to the others');
      expect(args.initialIndex, 1, reason: 'it opens on the one you tapped');
    });

    testWidgets('tapping the avatar views it instead of opening the picker', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_user(photos: photos)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('profile_avatar')));
      await tester.pumpAndSettle();

      expect(_pushed.single.name, AppRoutes.mediaViewer);
      expect((_pushed.single.arguments as MediaViewerArgs).initialIndex, 0);
    });

    testWidgets('with no photos the avatar has nothing to open', (tester) async {
      await tester.pumpWidget(_host(_user()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('profile_avatar')));
      await tester.pumpAndSettle();

      expect(_pushed, isEmpty,
          reason: 'an empty viewer is a black screen with a close button');
    });
  });

  group('a way through to the editor', () {
    testWidgets('Photos and Interests each lead to Edit Profile', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_user(photos: photos)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('profile_edit_photos')));
      await tester.pumpAndSettle();
      expect(_pushed.single.name, AppRoutes.editProfile);

      expect(find.byKey(const Key('profile_edit_interests')), findsNothing,
          reason: 'we navigated away; the second is checked on a fresh pump');
    });

    testWidgets('the Interests block leads there too', (tester) async {
      await tester.pumpWidget(_host(_user(photos: photos)));
      await tester.pumpAndSettle();

      // Interests sits below Photos, About and the stats row. ensureVisible,
      // not scrollUntilVisible: the page holds several nested GridViews, so
      // "the scrollable" is ambiguous.
      final button = find.byKey(const Key('profile_edit_interests'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(_pushed.single.name, AppRoutes.editProfile);
    });
  });

  group('interest chips', () {
    testWidgets('a catalogue interest renders its localised label', (
      tester,
    ) async {
      await tester.pumpWidget(_host(
        _user(interests: const ['Travel']),
        locale: const Locale('ko'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('여행'), findsOneWidget);
      expect(
        find.text('Travel'),
        findsNothing,
        reason: 'the stored token is an identifier, not display text',
      );
    });

    testWidgets('an off-catalogue interest still renders, as itself', (
      tester,
    ) async {
      // Registration accepted free text, so stored values exist that the
      // catalogue has never heard of. Dropping them would hide a user's own
      // data from them.
      await tester.pumpWidget(_host(
        _user(interests: const ['Speleology']),
        locale: const Locale('ko'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Speleology'), findsOneWidget);
    });
  });
}
