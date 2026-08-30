import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flame/core/i18n/supported_locales.dart';

void main() {
  // Phase D took the list to the full 32 the product asked for: nine new
  // languages, five regional variants, and Arabic and Urdu finally shipped.
  //
  // Arabic was held back at 35% coverage because two thirds of an RTL page in
  // LTR English reads worse than plain English. That reason expired when the
  // coverage did — both RTL locales are near-complete now, and rtl_layout_test
  // covers the mirroring.
  test('exposes the shipped locales in picker order', () {
    expect(kSupportedLocales.map((l) => l.toLanguageTag()).toList(), [
      // English first, then alphabetical by English name.
      'en',
      'ar', 'bn', 'ca', 'zh', 'zh-Hant', 'hr', 'cs', 'da', 'nl',
      'en-AU', 'en-CA', 'en-GB', 'fi', 'fr', 'fr-CA', 'de', 'hi', 'id', 'it',
      'ja', 'ko', 'nb', 'pt-BR', 'pt', 'ru', 'es-MX', 'es', 'th', 'tr', 'ur',
      'vi',
    ]);
  });

  test('the right-to-left locales ship', () {
    final tags = kSupportedLocales.map((l) => l.languageCode);
    expect(tags, contains('ar'));
    expect(tags, contains('ur'));
  });

  // The invariant that the original pt bug slipped through: app_pt.arb existed
  // and was translated, but nothing listed it, so no device could ever reach
  // it and every Portugal user read Brazilian. A file and a list entry are
  // only useful together — check both directions.
  group('the list and the ARB directory agree', () {
    String arbFor(Locale l) =>
        'lib/l10n/app_${l.toLanguageTag().replaceAll('-', '_')}.arb';

    test('every listed locale has an ARB', () {
      for (final locale in kSupportedLocales) {
        expect(File(arbFor(locale)).existsSync(), isTrue,
            reason: '${locale.toLanguageTag()} is offered but ${arbFor(locale)} '
                'does not exist');
      }
    });

    test('every ARB is reachable from the picker', () {
      final listed = kSupportedLocales.map(arbFor).toSet();
      final onDisk = Directory('lib/l10n')
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.arb'));

      for (final path in onDisk) {
        expect(listed, contains(path),
            reason: '$path is translated but no device can reach it — this is '
                'exactly how European Portuguese stayed invisible');
      }
    });
  });

  test('every locale has a non-empty display name', () {
    for (final locale in kSupportedLocales) {
      expect(displayNameOf(locale), isNotEmpty);
      expect(displayNameOf(locale), isNot(locale.toLanguageTag()),
          reason: '${locale.toLanguageTag()} falls through to the raw tag');
    }
  });

  test('display names are in the language itself', () {
    expect(displayNameOf(const Locale('de')), 'Deutsch');
    expect(displayNameOf(const Locale('ru')), 'Русский');
    expect(displayNameOf(const Locale('ja')), '日本語');
    expect(displayNameOf(const Locale('ko')), '한국어');
    expect(displayNameOf(const Locale('tr')), 'Türkçe');
    expect(displayNameOf(const Locale('id')), 'Bahasa Indonesia');
    expect(displayNameOf(const Locale('it')), 'Italiano');
    expect(displayNameOf(const Locale('hi')), 'हिन्दी');
    expect(displayNameOf(const Locale('th')), 'ไทย');
    expect(displayNameOf(const Locale('vi')), 'Tiếng Việt');
    expect(displayNameOf(const Locale('ar')), 'العربية');
    expect(displayNameOf(const Locale('ur')), 'اردو');
    expect(displayNameOf(const Locale('bn')), 'বাংলা');
    expect(displayNameOf(const Locale('ca')), 'Català');
    expect(displayNameOf(const Locale('cs')), 'Čeština');
    expect(displayNameOf(const Locale('da')), 'Dansk');
    expect(displayNameOf(const Locale('nl')), 'Nederlands');
    expect(displayNameOf(const Locale('fi')), 'Suomi');
    expect(displayNameOf(const Locale('hr')), 'Hrvatski');
    expect(displayNameOf(const Locale('nb')), 'Norsk bokmål');
    expect(displayNameOf(const Locale('zh')), '简体中文');
    expect(
        displayNameOf(Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')),
        '繁體中文');
  });

  // A picker that shows "English" three times tells the user nothing. Once a
  // variant ships, its base has to name its region too.
  test('locales sharing a language are distinguishable in the picker', () {
    expect(displayNameOf(const Locale('en')), 'English (US)');
    expect(displayNameOf(const Locale('en', 'GB')), 'English (UK)');
    expect(displayNameOf(const Locale('en', 'AU')), 'English (Australia)');
    expect(displayNameOf(const Locale('en', 'CA')), 'English (Canada)');
    expect(displayNameOf(const Locale('es')), 'Español (España)');
    expect(displayNameOf(const Locale('es', 'MX')), 'Español (México)');
    expect(displayNameOf(const Locale('fr')), 'Français (France)');
    expect(displayNameOf(const Locale('fr', 'CA')), 'Français (Canada)');
    expect(displayNameOf(const Locale('pt')), 'Português (Portugal)');
    expect(displayNameOf(const Locale('pt', 'BR')), 'Português (Brasil)');

    final names = kSupportedLocales.map(displayNameOf).toList();
    expect(names.toSet(), hasLength(names.length),
        reason: 'two locales show the same name in the picker');
  });
}
