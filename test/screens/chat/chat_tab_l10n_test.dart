import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-level, deliberately.
///
/// The Chat tab predates the localization sweep that covered profile and
/// settings, so it is the one tab that stays English in all thirteen locales. A
/// widget test in English cannot see that; only the source can.
void main() {
  const screens = [
    'lib/screens/chat/matches_screen.dart',
    'lib/screens/chat/archived_conversations_screen.dart',
    'lib/screens/chat/chat_search_screen.dart',
  ];

  test('no user-facing string literals remain in the chat tab', () {
    final offenders = <String>[];

    for (final path in screens) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Any prose literal, not just `Text('...')` on one line. Matching only
        // the single-line form missed the unmatch dialog's body and its confirm
        // label, both of which sit on the line AFTER `Text(`.
        //
        // Prose here means: a quoted literal holding a space and at least three
        // letters. That catches interpolated English too — 'Error loading
        // matches: \$error' is still English — while leaving identifiers like
        // 'msg-\${message.id}' alone.
        final trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
        if (trimmed.contains('context.l10n')) continue;
        // Two rules, because neither alone is enough. The prose rule needs a
        // space, so it misses single-word labels ('Messages', 'Retry',
        // 'Archived'); the Text() rule only sees the single-line form, so it
        // missed the unmatch dialog's body and confirm label. Together they
        // found seven strings the narrow version reported as clean.
        final prose = RegExp(r'''['"][^'"]*[A-Za-z]{3,}[^'"]* [^'"]*['"]''');
        final inText = RegExp(r'''(Text|tooltip:|hintText:)\s*\(?\s*(const\s+)?['"][A-Za-z]''');
        if (prose.hasMatch(line) || inText.hasMatch(line)) {
          offenders.add('$path:${i + 1} $trimmed');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'these do not translate:\n${offenders.join('\n')}');
  });
}
