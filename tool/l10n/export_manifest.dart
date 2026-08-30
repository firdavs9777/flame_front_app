// Phase C, step 1: produce what a translator actually needs.
//
//   dart run tool/l10n/export_manifest.dart [outDir]
//
// Writes one CSV per locale containing ONLY the strings that locale still needs
// — a string already translated is not re-sent and not paid for twice — plus
// the English source, the `@` description that says where it appears, and the
// ICU placeholders that must survive intact.
//
// CSV because every translation vendor and every spreadsheet opens it. The
// import side (import_translations.dart) reads the same shape back.
import 'dart:convert';
import 'dart:io';

const _template = 'lib/l10n/app_en.arb';
const _arbDir = 'lib/l10n';

/// See import_translations.dart. A machine-translated string is NOT done: it
/// ships so the locale is usable today, and it goes out for post-editing so a
/// person can replace it.
const _mtKey = '@@x-machine-translated';

final _placeholder = RegExp(r'\{[a-zA-Z0-9_]+\}');

Map<String, dynamic> _read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Map<String, String> _strings(Map<String, dynamic> arb) => {
      for (final e in arb.entries)
        if (!e.key.startsWith('@') && e.value is String)
          e.key: e.value as String,
    };

/// Escapes one CSV field per RFC 4180.
String _csv(String value) => '"${value.replaceAll('"', '""')}"';

void main(List<String> args) {
  final outDir = Directory(args.isEmpty ? 'build/l10n_manifest' : args.first)
    ..createSync(recursive: true);

  final templateArb = _read(_template);
  final en = _strings(templateArb);

  final locales = Directory(_arbDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.arb'))
      .map((f) {
        final n = f.uri.pathSegments.last;
        return n.substring('app_'.length, n.length - '.arb'.length);
      })
      .where((l) => l != 'en')
      .toList()
    ..sort();

  final summary = StringBuffer()
    ..writeln('locale,needed,post_edit,human_translated,total,percent_human');
  var grandTotal = 0;

  for (final locale in locales) {
    final localeArb = _read('$_arbDir/app_$locale.arb');
    final translated = _strings(localeArb);
    final machine =
        ((localeArb[_mtKey] as List?) ?? const []).cast<String>().toSet();
    // A regional variant (pt_BR beside pt) inherits everything it does not
    // override, so only its own overrides are its to translate.
    final inherits = locale.contains('_') &&
        !locale.endsWith('_Hant') &&
        File('$_arbDir/app_${locale.split('_').first}.arb').existsSync();

    final rows = <String>[];
    var done = 0, postEdit = 0;
    for (final entry in en.entries) {
      if (inherits && !translated.containsKey(entry.key)) continue;
      final current = translated[entry.key];
      // A value identical to the English source is untranslated, not a
      // coincidence: the harvest used the same rule.
      final isMachine = machine.contains(entry.key);
      final isDone = current != null &&
          current.trim().toLowerCase() != entry.value.trim().toLowerCase() &&
          !isMachine;
      if (isDone) {
        done++;
        continue;
      }
      if (isMachine) postEdit++;
      final meta = templateArb['@${entry.key}'];
      final description =
          meta is Map && meta['description'] is String ? meta['description'] as String : '';
      final placeholders =
          _placeholder.allMatches(entry.value).map((m) => m.group(0)!).join(' ');
      rows.add([
        _csv(entry.key),
        _csv(entry.value),
        _csv(description),
        _csv(placeholders),
        _csv(isMachine ? 'machine' : ''),
        _csv(isMachine ? (current ?? '') : ''),
        '""', // translation — the column the translator fills in
      ].join(','));
    }

    final file = File('${outDir.path}/$locale.csv');
    file.writeAsStringSync([
      'key,english,description,placeholders,source,current,translation',
      ...rows,
    ].join('\n'));

    grandTotal += rows.length;
    final total = inherits ? translated.length : en.length;
    final pct = total == 0 ? 100 : (100 * done / total).round();
    summary.writeln('$locale,${rows.length},$postEdit,$done,$total,$pct');
    stdout.writeln('  ${locale.padRight(9)} ${rows.length.toString().padLeft(4)} strings needed  '
        '(${postEdit.toString().padLeft(4)} of them post-edit, '
        '${pct.toString().padLeft(3)}% human-translated)');
  }

  File('${outDir.path}/summary.csv').writeAsStringSync(summary.toString());
  File('${outDir.path}/README.txt').writeAsStringSync('''
Flame translation request
=========================

One CSV per locale. Fill the LAST column ("translation") and return the files
with their names unchanged. Leave every other column exactly as it is.

Rules that matter:

  * Placeholders such as {count} or {name} must appear in your translation
    exactly as they appear in the "placeholders" column. They are substituted at
    runtime; a missing one renders a hole, a renamed one crashes that language
    only. Word order around them may change freely.

  * "description" says where the string appears. A word like "Match" is a noun
    on one screen and a verb on another.

  * Leave a row blank if you are unsure rather than guessing. A blank row is
    skipped on import and stays English; a wrong guess ships.

  * Rows with source="machine" are ALREADY LIVE in the app as machine output,
    shown to you in the "current" column. Post-edit them: correct what is wrong
    and keep what is right. A blank translation leaves the machine text in
    place, so blank means "the machine got it right", not "skipped".

  * Arabic and Urdu are read right-to-left. Do not add directional marks or
    reorder punctuation to compensate — the app mirrors its own layout.

Total strings across all locales: $grandTotal
See summary.csv for the per-locale counts.
''');

  stdout.writeln('\n  $grandTotal strings total -> ${outDir.path}');
}
