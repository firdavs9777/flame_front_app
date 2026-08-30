import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Guards for the failure modes that do not announce themselves.
//
// Phase B hit the worst of them: `flutter gen-l10n` ABORTS when an ARB's
// @@locale disagrees with its filename — and exits 0 while doing it. The ARBs
// looked perfect, the command looked clean, and not one new locale was
// generated. It was caught by listing the output directory rather than
// trusting the run. These tests make that impossible to ship.
//
// The placeholder gate is the other silent one: a translation that drops
// '{count}' compiles fine and throws, or renders a hole, only in that language.

final _arbDir = Directory('lib/l10n');
final _genDir = Directory('lib/l10n/gen');
final _placeholder = RegExp(r'\{([a-zA-Z0-9_]+)\}');

Map<String, dynamic> _read(File f) =>
    jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

List<File> get _arbs => _arbDir
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.arb'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

String _localeOf(File f) {
  final name = f.uri.pathSegments.last; // app_<locale>.arb
  return name.substring('app_'.length, name.length - '.arb'.length);
}

Map<String, String> _strings(Map<String, dynamic> arb) => {
      for (final e in arb.entries)
        if (!e.key.startsWith('@') && e.value is String)
          e.key: e.value as String,
    };

void main() {
  test('every ARB declares an @@locale matching its filename', () {
    for (final f in _arbs) {
      final locale = _localeOf(f);
      expect(
        _read(f)['@@locale'],
        locale,
        reason: 'app_$locale.arb declares a different @@locale. gen-l10n aborts '
            'on this and exits 0, generating NOTHING for any locale — which is '
            'exactly how zh_Hant silently blocked five other languages.',
      );
    }
  });

  test('every ARB has generated localizations', () {
    // The other half of the same trap: ARBs can look complete while the
    // generated output never picked them up.
    final generated = _genDir
        .listSync()
        .whereType<File>()
        .map((f) => f.readAsStringSync())
        .join('\n');

    for (final f in _arbs) {
      final locale = _localeOf(f);
      if (locale == 'en') continue;
      // AppLocalizationsPtBr, AppLocalizationsZhHant, AppLocalizationsAr …
      final className = 'AppLocalizations${locale.split('_').map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase()).join()}';
      expect(
        generated.contains('class $className '),
        isTrue,
        reason: 'app_$locale.arb has no generated class. Run flutter gen-l10n '
            'and CHECK ITS OUTPUT — a clean exit does not mean it ran.',
      );
    }
  });

  test('no translation adds, drops or renames a placeholder', () {
    final en = _strings(_read(File('lib/l10n/app_en.arb')));

    for (final f in _arbs) {
      final locale = _localeOf(f);
      if (locale == 'en') continue;
      final translated = _strings(_read(f));

      for (final entry in translated.entries) {
        final source = en[entry.key];
        if (source == null) continue;
        final expected = _placeholder
            .allMatches(source)
            .map((m) => m.group(1)!)
            .toSet();
        final actual = _placeholder
            .allMatches(entry.value)
            .map((m) => m.group(1)!)
            .toSet();
        expect(
          actual,
          expected,
          reason: '$locale/${entry.key} — a dropped placeholder renders a hole '
              'or throws, and only in that language.',
        );
      }
    }
  });

  test('no ARB carries a key English does not define', () {
    // A key removed from the template but left behind elsewhere is dead weight
    // that still gets sent to a translator and still gets paid for.
    final en = _strings(_read(File('lib/l10n/app_en.arb'))).keys.toSet();
    for (final f in _arbs) {
      final locale = _localeOf(f);
      if (locale == 'en') continue;
      final extra = _strings(_read(f)).keys.toSet().difference(en);
      expect(extra, isEmpty, reason: 'app_$locale.arb has orphaned keys');
    }
  });
}
