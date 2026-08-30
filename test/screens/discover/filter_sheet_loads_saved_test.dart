// Opening the filter sheet and tapping Apply used to WIPE the user's filters.
//
// FilterNotifier.initFromUser existed and nothing called it, so the sheet
// always opened on the const defaults — 18-50, 50km, no interests — no matter
// what the user had saved. savePreferencesToApi then unconditionally PATCHed
// all of them, so confirming a sheet you never edited overwrote your real
// filters with defaults.
//
// Two smaller defects rode along: copyWith could not put genderPreference back
// to null, so choosing "Everyone" silently kept the previous gender; and
// savePreferencesToApi returned early on null, so Everyone never persisted.
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/filter_provider.dart';

User _user({
  int minAge = 25,
  int maxAge = 34,
  double maxDistance = 12,
  Gender lookingFor = Gender.female,
  List<String> interestsFilter = const ['Travel', 'Coffee'],
}) =>
    User.fromJson({
      'id': 'u1', 'name': 'Alex', 'age': 30, 'bio': '',
      'interests': const <String>[], 'gender': 'male',
      'looking_for': lookingFor.toApiString(), 'photos': const <String>[],
      'preferences': {
        'min_age': minAge, 'max_age': maxAge, 'max_distance': maxDistance,
        'interests_filter': interestsFilter,
      },
    });

void main() {
  test('initFromUser loads what the user actually saved', () {
    final n = FilterNotifier()..initFromUser(_user());

    expect(n.state.minAge, 25);
    expect(n.state.maxAge, 34);
    expect(n.state.maxDistance, 12);
    expect(n.state.interests, ['Travel', 'Coffee']);
    expect(n.state.genderPreference, Gender.female);
  });

  test('the defaults are NOT what a saved profile looks like', () {
    // The bug hid behind this: a sheet showing 18/50/50 looks plausible, which
    // is exactly why nobody noticed it was ignoring stored values.
    const defaults = DiscoveryFilters();
    final saved = (FilterNotifier()..initFromUser(_user())).state;

    expect(saved.minAge, isNot(defaults.minAge));
    expect(saved.maxDistance, isNot(defaults.maxDistance));
    expect(saved.interests, isNot(defaults.interests));
  });

  test('lookingFor "other" opens as Everyone, not as a picked gender', () {
    final n = FilterNotifier()
      ..initFromUser(_user(lookingFor: Gender.other));

    expect(n.state.genderPreference, isNull,
        reason: 'the profile stores "everyone" as other; the sheet shows it '
            'as null, and pre-selecting Gender.other would show a choice the '
            'user never made');
  });

  test('choosing Everyone can clear a gender that was set', () {
    final n = FilterNotifier()..initFromUser(_user(lookingFor: Gender.female));
    expect(n.state.genderPreference, Gender.female);

    n.setGenderPreference(null);

    expect(n.state.genderPreference, isNull,
        reason: 'copyWith could not distinguish "null" from "not passed", so '
            'Everyone silently kept the previous gender');
  });

  test('a gender can still be chosen, and swapped', () {
    final n = FilterNotifier()..initFromUser(_user(lookingFor: Gender.other));

    n.setGenderPreference(Gender.male);
    expect(n.state.genderPreference, Gender.male);

    n.setGenderPreference(Gender.female);
    expect(n.state.genderPreference, Gender.female);
  });

  test('an untouched sheet round-trips the saved values unchanged', () {
    // The whole point: open, change nothing, Apply — and nothing moves.
    final user = _user();
    final n = FilterNotifier()..initFromUser(user);

    expect(n.state.minAge, user.minAgePreference);
    expect(n.state.maxAge, user.maxAgePreference);
    expect(n.state.maxDistance, user.maxDistancePreference);
    expect(n.state.interests, user.interestsFilter);
    expect(n.state.genderPreference, user.lookingFor);
  });
}
