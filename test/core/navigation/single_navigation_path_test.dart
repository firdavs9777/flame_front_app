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
  test('no screen builds its own route', () {
    final offenders = <String>[];
    for (final entity in Directory('lib/screens').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('MaterialPageRoute')) {
        offenders.add(entity.path);
      }
    }

    expect(offenders, isEmpty,
        reason: 'these build routes directly instead of pushing a name:\n'
            '${offenders.join('\n')}');
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
