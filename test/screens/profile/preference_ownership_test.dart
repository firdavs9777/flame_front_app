import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-level tests, deliberately.
///
/// The property is "there is exactly one editor for these preferences", which is
/// about where code lives rather than what one widget renders. A widget test would
/// pass happily while a second editor sat one screen away.
void main() {
  test('edit-profile contains no preferences editor', () {
    final source =
        File('lib/screens/profile/edit_profile/edit_profile_screen.dart').readAsStringSync();

    expect(source.contains('_PreferencesSection'), isFalse,
        reason: 'the Discover filter sheet owns discovery preferences');
    expect(source.contains('updatePreferences'), isFalse,
        reason: 'including showOnlineStatus, which lives in Settings');
  });

  test('exactly one screen writes discovery preferences', () {
    final writers = <String>[];
    for (final entity in Directory('lib/screens').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('setMaxDistance(') || source.contains('setAgeRange(')) {
        writers.add(entity.path);
      }
    }

    expect(writers, ['lib/screens/discover/discover_filters_screen.dart'],
        reason: 'three surfaces over one truth is what this removes');
  });

  test('settings does not link to edit profile', () {
    final source =
        File('lib/screens/settings/settings_screen.dart').readAsStringSync();

    expect(source.contains('EditProfileScreen'), isFalse,
        reason: 'Settings is reached FROM Profile, so pointing back is a loop');
  });
}
