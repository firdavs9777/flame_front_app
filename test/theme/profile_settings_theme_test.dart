import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Dark mode was configured and then overridden. This is a lint-like test rather
// than a golden: goldens on themed screens break on every palette change and
// get regenerated without being read, which makes them worse than nothing.
void main() {
  test('profile and settings use theme tokens, not hardcoded colours', () {
    final offenders = <String>[];
    // Colors.transparent and Colors.red are intentional: one is not a colour,
    // and destructive actions are red in both themes by convention.
    final banned = RegExp(
      r'Colors\.(white|black|grey|black87|white70|white60|white54)',
    );

    for (final dir in ['lib/screens/profile', 'lib/screens/settings']) {
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (banned.hasMatch(lines[i])) {
            offenders.add('${entity.path}:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these ignore the ColorScheme, so dark mode renders them wrong:\n'
          '${offenders.join('\n')}',
    );
  });
}
