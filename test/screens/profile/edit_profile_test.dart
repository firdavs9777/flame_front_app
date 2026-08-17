// The old edit-profile screen was one Form validated on submit: a bad age
// or a too-short name was only ever discovered after the user had stopped
// thinking about it, on the far side of a Save tap. This test drives the
// reworked, sectioned screen entirely off injected save callbacks — never a
// real UserService — so it can assert that validation runs BEFORE the
// callback is invoked, not merely that an error appears afterward.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/user_provider.dart';
import 'package:flame/screens/profile/edit_profile_screen.dart';
import 'package:flame/services/user_service.dart';
import 'package:flame/theme/app_theme.dart';

// Never actually invoked: the screen reads its initial data off
// currentUserProvider (seeded below via setUser) and every save in these
// tests goes through an injected callback, not this service.
class _FakeUserService extends UserService {}

// A 1x1 transparent PNG as a data URI. SmartImage routes `data:` sources to
// Image.memory, so a photo tile renders without CachedNetworkImage reaching
// for the network in a widget test.
const _tinyPng = 'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
    'q842iQAAAABJRU5ErkJggg==';

User _user({
  String name = 'Alex',
  int age = 28,
  String bio = 'Hello there',
  List<String> interests = const ['Travel', 'Coffee'],
  Gender lookingFor = Gender.female,
  int minAge = 21,
  int maxAge = 40,
  double maxDistance = 25,
  bool showOnlineStatus = true,
  List<String> photos = const <String>[],
}) {
  return User.fromJson({
    'id': 'u1',
    'name': name,
    'age': age,
    'bio': bio,
    'interests': interests,
    'gender': 'male',
    'looking_for': lookingFor.toApiString(),
    'photos': photos,
    'preferences': {
      'min_age': minAge,
      'max_age': maxAge,
      'max_distance': maxDistance,
      'show_online_status': showOnlineStatus,
    },
  });
}

Widget _host(
  User user, {
  AboutSave? saveAbout,
  InterestsSave? saveInterests,
  PreferencesSave? savePreferences,
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => CurrentUserNotifier(_FakeUserService())..setUser(user),
      ),
    ],
    child: MaterialApp(
      theme: theme,
      home: EditProfileScreen(
        saveAbout: saveAbout,
        saveInterests: saveInterests,
        savePreferences: savePreferences,
      ),
    ),
  );
}

void main() {
  group('About section', () {
    testWidgets(
      'an age below 18 is rejected before any request is made',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(_host(
          _user(),
          saveAbout: ({required name, required age, required bio}) async {
            calls++;
            return true;
          },
        ));

        await tester.enterText(find.byKey(const Key('about_age_field')), '15');
        await tester.ensureVisible(find.byKey(const Key('about_save_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('about_save_button')));
        await tester.pump();

        expect(
          calls,
          0,
          reason: 'an invalid age must never reach the save callback',
        );
      },
    );

    testWidgets(
      'a name shorter than 2 characters is rejected before any request',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(_host(
          _user(),
          saveAbout: ({required name, required age, required bio}) async {
            calls++;
            return true;
          },
        ));

        await tester.enterText(find.byKey(const Key('about_name_field')), 'A');
        await tester.ensureVisible(find.byKey(const Key('about_save_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('about_save_button')));
        await tester.pump();

        expect(
          calls,
          0,
          reason:
              'User.name has minlength: 2 server-side; catching this here '
              'saves a round trip and a confusing 422',
        );
      },
    );

    testWidgets(
      'saving About sends only name, age and bio — not preferences',
      (tester) async {
        String? capturedName;
        int? capturedAge;
        String? capturedBio;
        var interestsCalls = 0;
        var preferencesCalls = 0;
        await tester.pumpWidget(_host(
          _user(minAge: 21, maxAge: 40),
          saveAbout: ({required name, required age, required bio}) async {
            capturedName = name;
            capturedAge = age;
            capturedBio = bio;
            return true;
          },
          // Spies on the *other* two sections' save paths. Asserting on
          // these directly — rather than inferring "preferences untouched"
          // from unchanged provider state — matters because state would
          // also stay unchanged if a regression fell through to the real
          // (unmocked) UserService: Flutter's test binding stubs every HTTP
          // response to 400, and CurrentUserNotifier.updatePreferences only
          // mutates state on success, so an unrelated network failure would
          // make this assertion pass for the wrong reason.
          saveInterests: ({required lookingFor, required interests}) async {
            interestsCalls++;
            return true;
          },
          savePreferences: ({minAge, maxAge, maxDistance, showOnlineStatus}) async {
            preferencesCalls++;
            return true;
          },
        ));

        await tester.enterText(
          find.byKey(const Key('about_name_field')),
          'Alexandra',
        );
        await tester.enterText(find.byKey(const Key('about_age_field')), '29');
        await tester.enterText(
          find.byKey(const Key('about_bio_field')),
          'Updated bio',
        );
        await tester.ensureVisible(find.byKey(const Key('about_save_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('about_save_button')));
        await tester.pump();

        expect(capturedName, 'Alexandra');
        expect(capturedAge, 29);
        expect(capturedBio, 'Updated bio');
        expect(
          interestsCalls,
          0,
          reason: 'saving About must never touch the Interests save path',
        );
        expect(
          preferencesCalls,
          0,
          reason: 'saving About must never touch the Preferences save path',
        );
      },
    );

    testWidgets(
      'a failed save keeps the user\'s edits on screen',
      (tester) async {
        await tester.pumpWidget(_host(
          _user(name: 'Alex'),
          saveAbout: ({required name, required age, required bio}) async =>
              false,
        ));

        await tester.enterText(
          find.byKey(const Key('about_name_field')),
          'Changed Name',
        );
        await tester.ensureVisible(find.byKey(const Key('about_save_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('about_save_button')));
        await tester.pump();
        await tester.pump();

        expect(
          find.text('Changed Name'),
          findsOneWidget,
          reason: 'a failed save must not revert what the user typed',
        );
      },
    );
  });

  // Task 5 exists so these screens are dark-mode-correct; a rework with no
  // dark coverage would leave that claim untested for the file it most
  // applies to. A smoke test, not a golden — goldens on themed screens break
  // on every palette change and get regenerated without being read.
  group('renders without throwing', () {
    final themes = {'light': AppTheme.lightTheme, 'dark': AppTheme.darkTheme};

    for (final entry in themes.entries) {
      testWidgets('in ${entry.key} theme', (tester) async {
        await tester.pumpWidget(_host(_user(), theme: entry.value));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Photos'), findsOneWidget);
        expect(find.text('About'), findsOneWidget);
        // The section card title and the in-section field label are both
        // literally "Interests".
        expect(find.text('Interests'), findsNWidgets(2));
        expect(find.text('Preferences'), findsOneWidget);
      });
    }
  });

  group('Preferences section', () {
    testWidgets(
      'min age above max age is rejected before any request',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(_host(
          _user(minAge: 21, maxAge: 40),
          savePreferences: ({minAge, maxAge, maxDistance, showOnlineStatus}) async {
            calls++;
            return true;
          },
        ));

        await tester.enterText(
          find.byKey(const Key('preferences_min_age_field')),
          '45',
        );
        await tester.enterText(
          find.byKey(const Key('preferences_max_age_field')),
          '40',
        );
        await tester.ensureVisible(
          find.byKey(const Key('preferences_save_button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('preferences_save_button')));
        await tester.pump();

        expect(
          calls,
          0,
          reason:
              'the route rejects min_age > max_age with a 422; catch it '
              'client-side and save the round trip',
        );
      },
    );

    testWidgets(
      'a fractional max distance is not rounded away by an unrelated save',
      (tester) async {
        double? capturedDistance;
        await tester.pumpWidget(_host(
          _user(maxDistance: 24.6),
          savePreferences: ({minAge, maxAge, maxDistance, showOnlineStatus}) async {
            capturedDistance = maxDistance;
            return true;
          },
        ));

        // Never touch the distance field — only saving, as if the user only
        // meant to flip the online-status switch.
        await tester.ensureVisible(
          find.byKey(const Key('preferences_save_button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('preferences_save_button')));
        await tester.pump();

        expect(
          capturedDistance,
          24.6,
          reason:
              'rounding the field on load would silently rewrite the '
              "user's stored 24.6 to 25 on their next save",
        );
      },
    );

    // The route's schema is `max_distance: Field(ge=1, le=500)`
    // (flame_backend app/community/schemas.py:100). Only the floor was
    // effectively enforced, and it said "Enter a valid distance" without
    // saying which end was wrong.
    testWidgets(
      'a max distance above 500 is rejected before any request',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(_host(
          _user(),
          savePreferences: ({minAge, maxAge, maxDistance, showOnlineStatus}) async {
            calls++;
            return true;
          },
        ));

        await tester.enterText(
          find.byKey(const Key('preferences_max_distance_field')),
          '5000',
        );
        await tester.ensureVisible(
          find.byKey(const Key('preferences_save_button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('preferences_save_button')));
        await tester.pump();

        expect(calls, 0);
        expect(
          find.text('Maximum distance is 500 km'),
          findsOneWidget,
          reason: 'the message must name the bound that was hit',
        );
      },
    );

    testWidgets(
      'exactly 500 km is accepted — the bound is inclusive',
      (tester) async {
        double? captured;
        await tester.pumpWidget(_host(
          _user(),
          savePreferences: ({minAge, maxAge, maxDistance, showOnlineStatus}) async {
            captured = maxDistance;
            return true;
          },
        ));

        await tester.enterText(
          find.byKey(const Key('preferences_max_distance_field')),
          '500',
        );
        await tester.ensureVisible(
          find.byKey(const Key('preferences_save_button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('preferences_save_button')));
        await tester.pump();

        expect(
          captured,
          500,
          reason: 'le=500 means 500 is valid; an off-by-one here would '
              'block a legitimate value',
        );
      },
    );

    testWidgets(
      'a max distance below the floor names the floor',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(_host(
          _user(),
          savePreferences: ({minAge, maxAge, maxDistance, showOnlineStatus}) async {
            calls++;
            return true;
          },
        ));

        await tester.enterText(
          find.byKey(const Key('preferences_max_distance_field')),
          '0',
        );
        await tester.ensureVisible(
          find.byKey(const Key('preferences_save_button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('preferences_save_button')));
        await tester.pump();

        expect(calls, 0);
        expect(find.text('Minimum distance is 1 km'), findsOneWidget);
      },
    );
  });

  group('About section length ceiling', () {
    testWidgets(
      'a name longer than 50 characters is rejected before any request',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(_host(
          _user(),
          saveAbout: ({required name, required age, required bio}) async {
            calls++;
            return true;
          },
        ));

        await tester.enterText(
          find.byKey(const Key('about_name_field')),
          'A' * 51,
        );
        await tester.ensureVisible(find.byKey(const Key('about_save_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('about_save_button')));
        await tester.pump();

        expect(
          calls,
          0,
          reason:
              'User.name is maxlength 50 server-side; only the floor was '
              'checked, so a 51-character name went out and came back as a '
              'bare "Could not save"',
        );
        expect(
          find.text('Name must be 50 characters or fewer (currently 51)'),
          findsOneWidget,
        );
      },
    );

    testWidgets('exactly 50 characters is accepted', (tester) async {
      String? captured;
      await tester.pumpWidget(_host(
        _user(),
        saveAbout: ({required name, required age, required bio}) async {
          captured = name;
          return true;
        },
      ));

      await tester.enterText(
        find.byKey(const Key('about_name_field')),
        'A' * 50,
      );
      await tester.ensureVisible(find.byKey(const Key('about_save_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('about_save_button')));
      await tester.pump();

      expect(captured, 'A' * 50);
    });
  });

  // The Interests section had no Form and no validator at all, in the task
  // whose whole thesis is validating before the request. The route requires
  // 1 to 10 interests; the picker offers 16 chips with no floor and no cap.
  group('Interests section bounds', () {
    Future<void> tapSave(WidgetTester tester) async {
      await tester.ensureVisible(
        find.byKey(const Key('interests_save_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('interests_save_button')));
      await tester.pump();
    }

    testWidgets(
      'saving with no interests selected is rejected before any request',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(_host(
          _user(interests: const <String>[]),
          saveInterests: ({required lookingFor, required interests}) async {
            calls++;
            return true;
          },
        ));

        await tapSave(tester);

        expect(
          calls,
          0,
          reason:
              'interests has min_length=1 server-side; deselecting your last '
              'interest used to produce a bare "Could not save — try again"',
        );
        expect(find.text('Pick at least 1 interest'), findsOneWidget);
      },
    );

    testWidgets(
      'saving with 11 interests is rejected before any request',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(_host(
          _user(interests: const [
            'Travel', 'Music', 'Movies', 'Sports', 'Fitness', 'Food',
            'Art', 'Gaming', 'Reading', 'Photography', 'Coffee',
          ]),
          saveInterests: ({required lookingFor, required interests}) async {
            calls++;
            return true;
          },
        ));

        await tapSave(tester);

        expect(calls, 0, reason: 'interests has max_length=10 server-side');
        expect(
          find.text('Pick at most 10 interests — 11 are selected'),
          findsOneWidget,
          reason:
              'the message must say which bound was hit, and how far over',
        );
      },
    );

    testWidgets('exactly 10 interests is accepted', (tester) async {
      List<String>? captured;
      await tester.pumpWidget(_host(
        _user(interests: const [
          'Travel', 'Music', 'Movies', 'Sports', 'Fitness', 'Food',
          'Art', 'Gaming', 'Reading', 'Photography',
        ]),
        saveInterests: ({required lookingFor, required interests}) async {
          captured = interests;
          return true;
        },
      ));

      await tapSave(tester);

      expect(
        captured,
        hasLength(10),
        reason: 'max_length=10 means 10 is valid; the cap must not be '
            'off by one against a legitimate selection',
      );
      expect(find.byKey(const Key('interests_bounds_error')), findsNothing);
    });

    testWidgets(
      'a bounds message already on screen tracks the selection',
      (tester) async {
        await tester.pumpWidget(_host(
          _user(interests: const <String>[]),
          saveInterests: ({required lookingFor, required interests}) async =>
              true,
        ));

        await tapSave(tester);
        expect(find.byKey(const Key('interests_bounds_error')), findsOneWidget);

        // Selecting one interest makes the selection savable; the message
        // must not linger and contradict the screen.
        await tester.ensureVisible(find.text('Travel'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Travel'));
        await tester.pump();

        expect(find.byKey(const Key('interests_bounds_error')), findsNothing);
      },
    );
  });

  // "Set as main photo" called setMainPhotoAt -> reorderPhotos ->
  // PATCH /users/me/photos/reorder. The route exists and persists, but its
  // response serialises photos as {id, order, is_primary} with no `url`, and
  // Photo.fromJson defaults a missing url to ''. So the tap reported success
  // and then blanked every photo url in local state.
  group('photo options', () {
    testWidgets('offer no "Set as main photo" action', (tester) async {
      await tester.pumpWidget(_host(
        _user(photos: const [_tinyPng, _tinyPng]),
      ));
      await tester.pumpAndSettle();

      // The second tile's menu — the only one the item was ever shown on,
      // since it was hidden for index 0.
      await tester.tap(find.byIcon(Icons.more_vert).at(1));
      await tester.pumpAndSettle();

      expect(
        find.text('Delete photo'),
        findsOneWidget,
        reason: 'the sheet must actually be open, or the assertion below '
            'passes for the wrong reason',
      );
      expect(find.text('Set as main photo'), findsNothing);
    });
  });
}
