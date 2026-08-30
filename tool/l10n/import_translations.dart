// Phase C, step 2: merge returned translations back into the ARBs.
//
//   dart run tool/l10n/import_translations.dart <dir-of-returned-csvs> [--apply]
//
// Dry-run by default. Nothing is written until --apply, so a bad delivery is
// inspected before it touches the repo.
//
// The guards are the ones Phase B's harvest used, for the same reasons — this
// is the same operation with a different source, and a paid delivery deserves
// no more trust than a scraped one:
//
//   * a string already translated is never overwritten
//   * a translation whose ICU placeholders differ from the English is REFUSED,
//     because a dropped {count} renders a hole in that language alone
//   * a blank row, or one still equal to its English, is skipped rather than
//     counted as coverage
import 'dart:convert';
import 'dart:io';

const _arbDir = 'lib/l10n';
final _placeholder = RegExp(r'\{([a-zA-Z0-9_]+)\}');

Map<String, dynamic> _read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Map<String, String> _strings(Map<String, dynamic> arb) => {
      for (final e in arb.entries)
        if (!e.key.startsWith('@') && e.value is String)
          e.key: e.value as String,
    };

/// Minimal RFC 4180 reader: quoted fields, doubled quotes, newlines inside
/// quotes. Written out rather than pulled in as a dependency because it is
/// twenty lines and this runs in CI.
List<List<String>> parseCsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;

  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      if (row.any((f) => f.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  row.add(field.toString());
  if (row.any((f) => f.isNotEmpty)) rows.add(row);
  return rows;
}

class ImportResult {
  final int applied;
  final int skippedBlank;
  final int skippedAlreadyDone;
  final List<String> rejected;

  ImportResult(this.applied, this.skippedBlank, this.skippedAlreadyDone,
      this.rejected);
}

/// Merges [incoming] into [current] for one locale. Pure, so the rules are
/// testable without a filesystem.
ImportResult mergeTranslations({
  required Map<String, String> english,
  required Map<String, String> current,
  required Map<String, String> incoming,
  required Map<String, String> out,
}) {
  var applied = 0, blank = 0, alreadyDone = 0;
  final rejected = <String>[];

  out.addAll(current);

  for (final entry in incoming.entries) {
    final source = english[entry.key];
    if (source == null) {
      rejected.add('${entry.key}: not a key English defines');
      continue;
    }
    final value = entry.value.trim();
    if (value.isEmpty) {
      blank++;
      continue;
    }
    if (value.toLowerCase() == source.trim().toLowerCase()) {
      blank++;
      continue;
    }
    final existing = current[entry.key];
    if (existing != null &&
        existing.trim().toLowerCase() != source.trim().toLowerCase()) {
      alreadyDone++;
      continue;
    }
    final want = _placeholder.allMatches(source).map((m) => m.group(1)!).toSet();
    final got = _placeholder.allMatches(value).map((m) => m.group(1)!).toSet();
    if (!_setEquals(want, got)) {
      rejected.add('${entry.key}: placeholders $got, expected $want');
      continue;
    }
    out[entry.key] = value;
    applied++;
  }
  return ImportResult(applied, blank, alreadyDone, rejected);
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.every(b.contains);

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: import_translations.dart <dir> [--apply]');
    exit(64);
  }
  final dir = Directory(args.first);
  final apply = args.contains('--apply');
  if (!dir.existsSync()) {
    stderr.writeln('no such directory: ${dir.path}');
    exit(66);
  }

  final templateArb = _read('$_arbDir/app_en.arb');
  final english = _strings(templateArb);
  var totalApplied = 0, totalRejected = 0;

  final files = dir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    if (!file.path.endsWith('.csv')) continue;
    final locale = file.uri.pathSegments.last.replaceAll('.csv', '');
    if (locale == 'summary') continue;

    final target = File('$_arbDir/app_$locale.arb');
    if (!target.existsSync()) {
      stdout.writeln('  $locale: no app_$locale.arb — skipped');
      continue;
    }

    final rows = parseCsv(file.readAsStringSync());
    if (rows.isEmpty) continue;
    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    final keyIdx = header.indexOf('key');
    final valIdx = header.indexOf('translation');
    if (keyIdx < 0 || valIdx < 0) {
      stdout.writeln('  $locale: missing key/translation columns — skipped');
      continue;
    }

    final incoming = <String, String>{};
    for (final row in rows.skip(1)) {
      if (row.length <= valIdx) continue;
      incoming[row[keyIdx]] = row[valIdx];
    }

    final current = _strings(_read(target.path));
    final out = <String, String>{};
    final result = mergeTranslations(
      english: english,
      current: current,
      incoming: incoming,
      out: out,
    );

    totalApplied += result.applied;
    totalRejected += result.rejected.length;
    stdout.writeln('  ${locale.padRight(9)} +${result.applied} applied, '
        '${result.skippedBlank} blank, ${result.skippedAlreadyDone} already done, '
        '${result.rejected.length} REJECTED');
    for (final r in result.rejected) {
      stdout.writeln('      $r');
    }

    if (apply) {
      final body = <String, dynamic>{'@@locale': locale};
      for (final k in english.keys) {
        body[k] = out[k] ?? english[k]!;
      }
      target.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(body)}\n');
    }
  }

  stdout.writeln('\n  $totalApplied applied, $totalRejected rejected'
      '${apply ? '' : '  (DRY RUN — pass --apply to write)'}');
  if (apply) {
    stdout.writeln('  now run: flutter gen-l10n && flutter test test/l10n/');
  }
}
