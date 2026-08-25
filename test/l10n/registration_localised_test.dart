import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Files whose user-facing copy must come from the ARBs.
const _guarded = [
  'lib/screens/auth/registration/registration_flow.dart',
  'lib/screens/auth/registration/social_profile_completion_flow.dart',
  'lib/screens/auth/registration/step_wizard.dart',
  'lib/screens/auth/registration/steps/step_email_password.dart',
  'lib/screens/auth/registration/steps/step_profile_info.dart',
  'lib/screens/auth/registration/steps/step_looking_for.dart',
  'lib/screens/auth/registration/steps/step_bio_interests.dart',
  'lib/screens/auth/registration/steps/step_photos.dart',
];

/// A quoted sentence: starts with a capital, contains a space, three or more
/// characters. Deliberately crude — it catches copy, not identifiers.
final _sentence = RegExp(r"""['"][A-Z][a-z]+ [^'"]{3,}['"]""");

/// Lines that are allowed to carry an English sentence: debug output, comments,
/// asset paths, and API string constants.
bool _exempt(String line) {
  final t = line.trimLeft();
  return t.startsWith('//') ||
      t.startsWith('///') ||
      t.startsWith('*') ||
      t.contains('debugPrint') ||
      t.contains('assets/');
}

void main() {
  for (final path in _guarded) {
    test('$path has no hardcoded user-facing copy', () {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is missing');

      final offenders = <String>[];
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_exempt(lines[i])) continue;
        if (_sentence.hasMatch(lines[i])) {
          offenders.add('  ${i + 1}: ${lines[i].trim()}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Move these into lib/l10n/app_en.arb and read them through '
            'context.l10n:\n${offenders.join('\n')}',
      );
    });
  }
}
