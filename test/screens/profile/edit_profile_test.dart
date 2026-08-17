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

// Never actually invoked: the screen reads its initial data off
// currentUserProvider (seeded below via setUser) and every save in these
// tests goes through an injected callback, not this service.
class _FakeUserService extends UserService {}

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
}) {
  return User.fromJson({
    'id': 'u1',
    'name': name,
    'age': age,
    'bio': bio,
    'interests': interests,
    'gender': 'male',
    'looking_for': lookingFor.toApiString(),
    'photos': <String>[],
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
}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => CurrentUserNotifier(_FakeUserService())..setUser(user),
      ),
    ],
    child: MaterialApp(
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
        await tester.pumpWidget(_host(
          _user(minAge: 21, maxAge: 40),
          saveAbout: ({required name, required age, required bio}) async {
            capturedName = name;
            capturedAge = age;
            capturedBio = bio;
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

        // The callback's own signature is the independence guarantee: it has
        // no parameter through which minAge/maxAge/interests could travel.
        // Saving About must not have touched the Preferences the user
        // arrived with.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(EditProfileScreen)),
        );
        final user = container.read(currentUserProvider).valueOrNull;
        expect(user!.minAgePreference, 21);
        expect(user.maxAgePreference, 40);
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
  });
}
