import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-level, deliberately.
///
/// The property is "there is exactly one way to reach a screen" — about where
/// navigation lives, not what any widget renders. A widget test passes happily
/// while a screen one tap away builds its own MaterialPageRoute, and that screen
/// is then unreachable by name: a push-notification handler cannot call a
/// closure inside somebody's onTap.
void main() {
  /// welcome_screen builds two PageRouteBuilders by hand, for the slide
  /// transition into login and registration. They stay: both are pre-auth, so
  /// no notification or deep link can target them, and routing them would mean
  /// either losing the animation or teaching the route table about transitions.
  ///
  /// Listed explicitly rather than left to a narrower pattern. An earlier version
  /// of this test only looked for MaterialPageRoute, so it passed while these two
  /// existed — a test that read as "nothing builds its own route" while two
  /// things did.
  const allowed = {'lib/screens/auth/welcome_screen.dart'};

  test('no screen builds its own route', () {
    final offenders = <String>[];
    for (final entity in Directory('lib/screens').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (allowed.contains(entity.path)) continue;
      final source = entity.readAsStringSync();
      if (source.contains('MaterialPageRoute') ||
          source.contains('PageRouteBuilder')) {
        offenders.add(entity.path);
      }
    }

    expect(offenders, isEmpty,
        reason: 'these build routes directly instead of pushing a name:\n'
            '${offenders.join('\n')}');
  });

  test('the allowlist still describes reality', () {
    // If welcome_screen stops hand-rolling routes, this exemption should go
    // rather than sit here implying a constraint that no longer exists.
    for (final path in allowed) {
      final source = File(path).readAsStringSync();
      expect(source.contains('PageRouteBuilder') ||
              source.contains('MaterialPageRoute'), isTrue,
          reason: '$path no longer builds its own route — drop it from allowed');
    }
  });

  test('the router is the only place MaterialPageRoute appears', () {
    // Not a ban on the class — the router itself needs it. This pins the
    // location so the previous test cannot be satisfied by moving the problem.
    final users = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains('l10n/gen')) continue;
      if (entity.readAsStringSync().contains('MaterialPageRoute')) {
        users.add(entity.path);
      }
    }

    expect(users, ['lib/core/navigation/app_router.dart']);
  });
}
