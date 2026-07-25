import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _readArb(String name) {
  final file = File('lib/l10n/$name');
  expect(file.existsSync(), isTrue, reason: '$name not found at ${file.path}');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Set<String> _stringKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  test('every key in app_en.arb has a translation in all other ARBs', () {
    final en = _stringKeys(_readArb('app_en.arb'));
    expect(en, isNotEmpty, reason: 'app_en.arb should define some keys');

    const others = [
      'app_es.arb',
      'app_pt.arb',
      'app_pt_BR.arb',
      'app_fr.arb',
      'app_de.arb',
      'app_ru.arb',
      'app_ja.arb',
      'app_ko.arb',
      'app_zh.arb',
      'app_tr.arb',
      'app_id.arb',
    ];

    for (final name in others) {
      final keys = _stringKeys(_readArb(name));
      expect(
        keys,
        equals(en),
        reason: '$name key set must exactly match app_en.arb',
      );
    }
  });
}
