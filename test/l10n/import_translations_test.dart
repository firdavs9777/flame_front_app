import 'package:flutter_test/flutter_test.dart';

import '../../tool/l10n/import_translations.dart';

// The import pipeline decides what a paid translation delivery is allowed to do
// to the ARBs. A delivery deserves no more trust than the scrape Phase B did:
// vendors hand back blank rows, rows still in English, and — the one that
// actually breaks the app — rows where {count} was translated away.
//
// mergeTranslations is pure so these rules are pinned without a filesystem.

const _english = {
  'greeting': 'Hello',
  'counted': 'You have {count} matches',
  'named': 'Hi {name}, welcome',
};

Map<String, String> _merge(
  Map<String, String> current,
  Map<String, String> incoming,
  void Function(ImportResult) check, {
  Set<String> machine = const {},
}) {
  final out = <String, String>{};
  check(mergeTranslations(
    english: _english,
    current: current,
    incoming: incoming,
    out: out,
    machine: machine,
  ));
  return out;
}

void main() {
  group('machine-translated strings are replaceable, human ones are not', () {
    // Phase D shipped machine translation for thousands of strings. Without
    // provenance every one of them would read as "already translated" and a
    // paid delivery would be skipped in full — the machine output would be
    // permanent. These two tests are the difference.
    test('a delivery replaces a machine-translated string', () {
      final out = _merge(
        {'greeting': 'Hola-maquina'},
        {'greeting': 'Hola'},
        (r) {
          expect(r.applied, 1);
          expect(r.skippedAlreadyDone, 0);
          expect(r.appliedKeys, contains('greeting'));
        },
        machine: {'greeting'},
      );
      expect(out['greeting'], 'Hola');
    });

    test('a delivery still cannot overwrite a human translation', () {
      final out = _merge(
        {'greeting': 'Hola-humano'},
        {'greeting': 'Hola'},
        (r) {
          expect(r.applied, 0);
          expect(r.skippedAlreadyDone, 1);
        },
        machine: const {},
      );
      expect(out['greeting'], 'Hola-humano');
    });

    test('a machine string still cannot drop a placeholder', () {
      _merge(
        {'counted': 'Tienes {count} coincidencias (maquina)'},
        {'counted': 'Tienes muchas coincidencias'},
        (r) {
          expect(r.applied, 0);
          expect(r.rejected, hasLength(1));
        },
        machine: {'counted'},
      );
    });
  });

  test('applies a clean translation', () {
    final out = _merge(
      {'greeting': 'Hello'},
      {'greeting': 'Hola'},
      (r) => expect(r.applied, 1),
    );
    expect(out['greeting'], 'Hola');
  });

  test('never overwrites a string already translated', () {
    final out = _merge(
      {'greeting': 'Hola'},
      {'greeting': 'Buenas'},
      (r) {
        expect(r.applied, 0);
        expect(r.skippedAlreadyDone, 1);
      },
    );
    expect(out['greeting'], 'Hola',
        reason: 'paid-for work already in the repo is not overwritten by a '
            'later delivery of the same key');
  });

  test('refuses a translation that drops a placeholder', () {
    final out = _merge(
      {'counted': 'You have {count} matches'},
      {'counted': 'Tienes coincidencias'},
      (r) {
        expect(r.applied, 0);
        expect(r.rejected.single, contains('counted'));
      },
    );
    expect(out['counted'], 'You have {count} matches',
        reason: 'a dropped placeholder renders a hole in that language alone');
  });

  test('refuses a translation that renames a placeholder', () {
    _merge(
      {'named': 'Hi {name}, welcome'},
      {'named': 'Hola {nombre}, bienvenido'},
      (r) {
        expect(r.applied, 0);
        expect(r.rejected.single, contains('named'));
      },
    );
  });

  test('accepts a placeholder moved to a different position', () {
    final out = _merge(
      {'named': 'Hi {name}, welcome'},
      {'named': 'Bienvenido, {name}'},
      (r) => expect(r.applied, 1),
    );
    expect(out['named'], 'Bienvenido, {name}',
        reason: 'word order around a placeholder is exactly what translation is');
  });

  test('skips a blank row instead of blanking the string', () {
    final out = _merge(
      {'greeting': 'Hello'},
      {'greeting': '   '},
      (r) {
        expect(r.applied, 0);
        expect(r.skippedBlank, 1);
      },
    );
    expect(out['greeting'], 'Hello');
  });

  test('skips a row handed back still in English', () {
    _merge(
      {'greeting': 'Hello'},
      {'greeting': 'hello'},
      (r) {
        expect(r.applied, 0);
        expect(r.skippedBlank, 1,
            reason: 'an untranslated row must not count as coverage');
      },
    );
  });

  test('rejects a key English does not define', () {
    _merge(
      {'greeting': 'Hello'},
      {'ghostKey': 'Fantasma'},
      (r) {
        expect(r.applied, 0);
        expect(r.rejected.single, contains('ghostKey'));
      },
    );
  });

  group('CSV parsing survives what spreadsheets produce', () {
    test('reads quoted fields, embedded commas and doubled quotes', () {
      final rows = parseCsv(
        'key,translation\n'
        '"a","Hola, ¿qué tal?"\n'
        '"b","She said ""hi"""\n',
      );
      expect(rows[1], ['a', 'Hola, ¿qué tal?']);
      expect(rows[2], ['b', 'She said "hi"']);
    });

    test('reads a newline inside a quoted field', () {
      final rows = parseCsv('key,translation\n"a","line one\nline two"\n');
      expect(rows[1][1], 'line one\nline two');
    });

    test('tolerates CRLF', () {
      final rows = parseCsv('key,translation\r\n"a","Hola"\r\n');
      expect(rows.length, 2);
      expect(rows[1], ['a', 'Hola']);
    });
  });
}
