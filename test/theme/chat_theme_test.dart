import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Wider than the profile gate's original list, which banned white|black|grey and
/// nothing else — so Colors.blue and Colors.amber passed a test whose name
/// promised otherwise.
final _banned = RegExp(
  r'Colors\.(white|black|grey|gray|blue|amber|green|orange|purple|pink|teal'
  r'|cyan|indigo|lime|brown|yellow)'
  r'(\d{2,3})?\b',
);

void main() {
  test('chat uses semantic tokens, not colour literals', () {
    final offenders = <String>[];
    for (final entity
        in Directory('lib/screens/chat').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // Colors.transparent is not a colour, and Colors.red is measured legible
        // in both themes; both are deliberately spared.
        if (_banned.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'replace with a token from lib/theme/app_tokens.dart:\n'
            '${offenders.join('\n')}');
  });
}
