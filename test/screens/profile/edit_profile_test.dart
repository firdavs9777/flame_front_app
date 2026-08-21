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
import 'package:flame/screens/profile/edit_profile/edit_profile_screen.dart';
import 'package:flame/services/user_service.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/core/date/age.dart';
import 'package:flame/l10n/gen/app_localizations.dart';

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
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => CurrentUserNotifier(_FakeUserService())..setUser(user),
      ),
    ],
    child: MaterialApp(
      // Interest chips read their labels from the ARBs now, so the section needs
      // localizations to build.
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme,
      home: EditProfileScreen(
        saveAbout: saveAbout,
        saveInterests: saveInterests,
      ),
    ),
  );
}

void main() {
  group('About section', () {
    // Age is a bounded date picker rather than a number field, so an
    // ineligible age is unreachable instead of rejected after the fact. The
    // arithmetic behind the bounds is covered directly in
    // test/core/date/age_test.dart; these two assert that this screen actually
    // hands those bounds to the picker, and that nothing can be typed.
    testWidgets('the age picker cannot reach an age below 18', (tester) async {
      await tester.pumpWidget(_host(_user(age: 28)));

      await tester.ensureVisible(find.byKey(const Key('about_age_picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('about_age_picker')));
      await tester.pumpAndSettle();

      final dialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      final now = DateTime.now();

      // The newest selectable birthday is exactly 18 years ago, so every
      // selectable date yields 18 or more.
      expect(ageOn(dialog.lastDate, now: now), 18);
      expect(ageOn(dialog.firstDate, now: now), 100);
      expect(
        dialog.initialDate == null ? null : ageOn(dialog.initialDate!, now: now),
        28,
        reason: 'the picker should open on the age the user already has',
      );
    });

    testWidgets('an age cannot be typed at all', (tester) async {
      await tester.pumpWidget(_host(_user(age: 28)));

      expect(find.byKey(const Key('about_age_field')), findsNothing);
      expect(find.byKey(const Key('about_age_value')), findsOneWidget);
      expect(find.text('28'), findsOneWidget);
    });

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
        ));

        await tester.enterText(
          find.byKey(const Key('about_name_field')),
          'Alexandra',
        );
        await tester.enterText(
          find.byKey(const Key('about_bio_field')),
          'Updated bio',
        );
        await tester.ensureVisible(find.byKey(const Key('about_save_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('about_save_button')));
        await tester.pump();

        expect(capturedName, 'Alexandra');
        // Untouched, so it carries the user's existing age — the point of this
        // test is which fields travel, not what they contain.
        expect(capturedAge, 28);
        expect(capturedBio, 'Updated bio');
        expect(
          interestsCalls,
          0,
          reason: 'saving About must never touch the Interests save path',
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
        // No Preferences card: the Discover filter sheet owns those now.
        expect(find.text('Preferences'), findsNothing);
      });
    }
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
