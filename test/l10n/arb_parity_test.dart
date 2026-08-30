import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Parity is enumerated from the directory, never from a hand-written list: the
// old hardcoded list silently skipped six locales, so ar/hi/it/th/vi/zh_Hant
// could drift out of parity and no test would say so.

final _arbDir = Directory('lib/l10n');

Map<String, dynamic> _readArb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _stringKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

List<String> get _locales => _arbDir
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

/// A locale like `pt_BR` that also ships a base `pt`. gen-l10n generates it as
/// a subclass of the base, so it only needs to carry what actually differs.
bool _inheritsFromBase(String locale) {
  if (!locale.contains('_')) return false;
  final base = locale.split('_').first;
  // zh_Hant is a script, not a region: it shares no text with zh and must be
  // complete on its own.
  if (locale.endsWith('_Hant')) return false;
  return File('lib/l10n/app_$base.arb').existsSync();
}

void main() {
  late Set<String> en;

  setUpAll(() => en = _stringKeys(_readArb('app_en.arb')));

  test('app_en.arb defines keys', () {
    expect(en, isNotEmpty);
  });

  test('every base-language ARB matches app_en.arb key for key', () {
    final bases = _locales.where((l) => !_inheritsFromBase(l)).toList();
    expect(bases, isNotEmpty, reason: 'no base locales found — glob broken?');

    for (final locale in bases) {
      expect(
        _stringKeys(_readArb('app_$locale.arb')),
        equals(en),
        reason: 'app_$locale.arb key set must exactly match app_en.arb',
      );
    }
  });

  test('every regional-variant ARB overrides a subset of app_en.arb', () {
    // A variant carries only its genuine differences — a full copy would be
    // noise, and would report as 0% translated forever.
    for (final locale in _locales.where(_inheritsFromBase)) {
      final keys = _stringKeys(_readArb('app_$locale.arb'));
      expect(keys, isNotEmpty, reason: 'app_$locale.arb overrides nothing');
      expect(
        keys.difference(en),
        isEmpty,
        reason: 'app_$locale.arb overrides keys English does not define',
      );
    }
  });
}
