import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-level tests, deliberately.
///
/// The property is "a release artifact cannot be signed with the shared debug
/// key", which lives in Gradle configuration rather than in any widget. There is
/// nothing to render and no Dart symbol to reach for — but it is worth a test,
/// because the failure it guards is invisible until the Play Console rejects an
/// upload, and the config it replaced shipped that way for months behind a TODO.
void main() {
  late String gradle;

  setUpAll(() {
    gradle = File('android/app/build.gradle.kts').readAsStringSync();
  });

  test('release does not unconditionally sign with the debug key', () {
    // The old line, exactly: `signingConfig = signingConfigs.getByName("debug")`
    // as the only statement in the release block. A debug fallback is still
    // allowed, but only as the else of a keystore check.
    final debugUses = 'signingConfigs.getByName("debug")'.allMatches(gradle).length;
    expect(debugUses, lessThanOrEqualTo(1),
        reason: 'debug signing should appear once at most, as a fallback');
    expect(gradle.contains('hasReleaseKeystore'), isTrue,
        reason: 'the release signing config must be chosen by whether a keystore exists');
  });

  test('a release keystore is read from an untracked properties file', () {
    expect(gradle.contains('key.properties'), isTrue);
    for (final key in ['storeFile', 'storePassword', 'keyAlias', 'keyPassword']) {
      expect(gradle.contains(key), isTrue, reason: '$key must come from key.properties');
    }
  });

  test('an uploadable artifact is refused when no keystore is configured', () {
    // Falling back to debug keeps `flutter run --release` working, so the
    // fallback alone cannot protect an upload. These two task names are the ones
    // that produce something submittable.
    expect(gradle.contains('bundleRelease'), isTrue);
    expect(gradle.contains('assembleRelease'), isTrue);
    expect(gradle.contains('GradleException'), isTrue,
        reason: 'the build must fail rather than emit a debug-signed bundle');
  });

  test('signing secrets are gitignored and never committed', () {
    final ignore = File('android/.gitignore').readAsStringSync();
    expect(ignore.contains('key.properties'), isTrue);
    expect(ignore.contains('*.jks') || ignore.contains('**/*.jks'), isTrue);
    expect(ignore.contains('*.keystore') || ignore.contains('**/*.keystore'), isTrue);

    // The real file must not exist in the tree the tests run against: if it did,
    // it would mean a keystore path and its passwords had been checked in.
    expect(File('android/key.properties').existsSync(), isFalse,
        reason: 'key.properties is per-developer and must stay out of the repo');
    expect(File('android/key.properties.example').existsSync(), isTrue,
        reason: 'the example documents the four keys without carrying secrets');
  });

  test('the example properties file carries no filled-in secrets', () {
    final example = File('android/key.properties.example').readAsStringSync();
    for (final line in example.split('\n')) {
      if (line.startsWith('storePassword') || line.startsWith('keyPassword')) {
        expect(line.split('=').last.trim(), isEmpty,
            reason: 'the example must never carry a real password: $line');
      }
    }
  });
}
