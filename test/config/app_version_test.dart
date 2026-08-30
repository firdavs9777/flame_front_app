import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flame/config/app_version.dart';

// The Settings footer and the licence page read kAppVersion; the build stamps
// pubspec.yaml. Nothing links the two, so this does.
void main() {
  test('kAppVersion matches the version in pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    // `version: 1.0.0+1` — the build number after '+' is not shown to users.
    final pubspec = line.split(':')[1].trim().split('+').first;

    expect(
      kAppVersion,
      pubspec,
      reason: 'lib/config/app_version.dart and pubspec.yaml disagree. Users '
          'would see one version and the store would list the other.',
    );
  });
}
