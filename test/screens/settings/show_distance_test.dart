// Scope A made distance real and taught the server to honour
// preferences.showDistance, then shipped no control for it — and left a comment
// in edit-profile explaining that the absence was deliberate because nothing
// computed a distance, which had stopped being true the same day.
//
// These drive the real CurrentUserNotifier over a recording UserService, so they
// assert the request goes out rather than that a local flag moved.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/user_provider.dart';
import 'package:flame/screens/settings/settings_screen.dart';
import 'package:flame/services/user_service.dart';

class _RecordingUserService extends UserService {
  int preferenceCalls = 0;
  bool? lastShowDistance;
  bool succeeds = true;

  @override
  Future<ServiceResult<Map<String, dynamic>>> updatePreferences({
    int? minAge,
    int? maxAge,
    double? maxDistance,
    bool? showDistance,
    bool? showOnlineStatus,
    List<String>? interestsFilter,
  }) async {
    preferenceCalls++;
    lastShowDistance = showDistance;
    return succeeds
        ? ServiceResult.success(const {})
        : ServiceResult.failure('nope');
  }
}

User _user({bool showDistance = true}) => User.fromJson({
      'id': 'u1', 'name': 'Alex', 'age': 28, 'bio': '',
      'interests': <String>[], 'gender': 'male', 'looking_for': 'female',
      'photos': <String>[],
      'preferences': {'show_distance': showDistance},
    });

Widget _host(User user, _RecordingUserService service) => ProviderScope(
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

const _switchKey = Key('settings_show_distance_switch');

void main() {
  testWidgets('the switch shows the stored value, not a local default',
      (tester) async {
    await tester.pumpWidget(_host(_user(showDistance: false), _RecordingUserService()));
    await tester.pump();

    expect(tester.widget<SwitchListTile>(find.byKey(_switchKey)).value, isFalse);
  });

  testWidgets('toggling writes showDistance to the server', (tester) async {
    final service = _RecordingUserService();
    await tester.pumpWidget(_host(_user(), service));
    await tester.pump();

    await tester.tap(find.byKey(_switchKey));
    await tester.pumpAndSettle();

    expect(service.preferenceCalls, 1);
    expect(service.lastShowDistance, isFalse,
        reason: 'the backend already honours this field — Scope A landed the '
            'enforcement without the control');
  });

  testWidgets('a failed write leaves the stored value showing', (tester) async {
    final service = _RecordingUserService()..succeeds = false;
    await tester.pumpWidget(_host(_user(), service));
    await tester.pump();

    await tester.tap(find.byKey(_switchKey));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(find.byKey(_switchKey)).value, isTrue,
        reason: 'a switch that stays flipped after the server refused is lying '
            'about server state');
  });

  testWidgets('the switch is inert while the user is still loading',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => CurrentUserNotifier(_RecordingUserService()),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const SettingsScreen(),
      ),
    ));
    await tester.pump();

    expect(tester.widget<SwitchListTile>(find.byKey(_switchKey)).onChanged, isNull,
        reason: 'visibly inert is honest about not knowing the value yet');
  });
}
