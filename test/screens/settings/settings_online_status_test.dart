// "Show Online Status" existed twice, in two directories, disagreeing.
//
// Settings' copy was wired to `settingsProvider`, whose
// `toggleShowOnlineStatus` mutated in-memory state and nothing else — no
// request, not even a SharedPreferences write. So the switch flipped, the
// server kept broadcasting the user as online, a restart restored the old
// value, and Edit Profile → Preferences (which is server-backed) showed the
// opposite. Task 4 of this plan deleted a method to prevent exactly this
// shape; Task 6 recreated it four commits later. Neither scoped review could
// see it, because the two controls live in different directories.
//
// These tests drive the real CurrentUserNotifier over a recording
// UserService, so they assert the request actually goes out rather than that
// some local flag moved.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/user_provider.dart';
import 'package:flame/screens/settings/settings_screen.dart';
import 'package:flame/services/user_service.dart';

class _RecordingUserService extends UserService {
  int preferenceCalls = 0;
  bool? lastShowOnlineStatus;
  bool succeeds = true;

  @override
  Future<ServiceResult<Map<String, dynamic>>> updatePreferences({
    int? minAge,
    int? maxAge,
    double? maxDistance,
    bool? showDistance,
    bool? showOnlineStatus,
  }) async {
    preferenceCalls++;
    lastShowOnlineStatus = showOnlineStatus;
    return succeeds
        ? ServiceResult.success(const {})
        : ServiceResult.failure('nope');
  }
}

User _user({bool showOnlineStatus = true}) {
  return User.fromJson({
    'id': 'u1',
    'name': 'Alex',
    'age': 28,
    'bio': '',
    'interests': <String>[],
    'gender': 'male',
    'looking_for': 'female',
    'photos': <String>[],
    'preferences': {'show_online_status': showOnlineStatus},
  });
}

Widget _host(User user, _RecordingUserService service) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => CurrentUserNotifier(service)..setUser(user),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: const SettingsScreen(),
    ),
  );
}

const _switchKey = Key('settings_show_online_switch');

void main() {
  testWidgets(
    'the switch shows the current user\'s stored value, not a local default',
    (tester) async {
      final service = _RecordingUserService();
      // AppSettings used to default showOnlineStatus to true, so a screen
      // reading local state would show ON here and lie about the account.
      await tester.pumpWidget(_host(_user(showOnlineStatus: false), service));
      await tester.pump();

      expect(
        tester.widget<SwitchListTile>(find.byKey(_switchKey)).value,
        isFalse,
        reason:
            'the displayed value must come from the stored preference, or '
            'Settings and Edit Profile can show opposite answers',
      );
    },
  );

  testWidgets(
    'toggling the switch sends the preference to the server',
    (tester) async {
      final service = _RecordingUserService();
      await tester.pumpWidget(_host(_user(showOnlineStatus: true), service));
      await tester.pump();

      await tester.tap(find.byKey(_switchKey));
      await tester.pump();

      expect(
        service.preferenceCalls,
        1,
        reason:
            'the old path mutated in-memory state only — no request and not '
            'even a SharedPreferences write, so a restart undid it',
      );
      expect(service.lastShowOnlineStatus, isFalse);
    },
  );

  testWidgets(
    'a successful toggle is reflected in the switch',
    (tester) async {
      final service = _RecordingUserService();
      await tester.pumpWidget(_host(_user(showOnlineStatus: true), service));
      await tester.pump();

      await tester.tap(find.byKey(_switchKey));
      await tester.pump();

      expect(
        tester.widget<SwitchListTile>(find.byKey(_switchKey)).value,
        isFalse,
      );
    },
  );

  // The spec claims "Dead controls in profile/settings — none, unlike chat".
  // These two were already false at the branch base: `discoveryEnabled` and
  // `showDistance` on AppSettings were read only by the switch that set them.
  //
  // "Show Distance" must not come back as a server-backed toggle either:
  // `format_public_user` reports distance only when the *target* user allows
  // it and `toDiscoverUser` hardcodes 0, so the toggle would govern a number
  // that always reads zero — the dead-button pattern the spec rejects.
  group('dead controls are gone', () {
    testWidgets('no "Show me in discovery" control', (tester) async {
      await tester.pumpWidget(_host(_user(), _RecordingUserService()));
      await tester.pump();

      expect(find.text('Show me in discovery'), findsNothing);
      expect(find.text('Discovery'), findsNothing);
    });

    testWidgets('no "Show Distance" control', (tester) async {
      await tester.pumpWidget(_host(_user(), _RecordingUserService()));
      await tester.pump();

      expect(find.text('Show Distance'), findsNothing);
      expect(find.text('Show distance on profile'), findsNothing);
    });
  });
}
