import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flame/core/i18n/supported_locales.dart';

void main() {
  // Phase B added six languages by harvesting BananaTalk's translations for
  // strings whose English is identical. Five are listed here; Arabic is not.
  //
  // Arabic sits at 35% translated AND reads right-to-left, so listing it would
  // put two thirds of the UI in left-to-right English inside a mirrored page —
  // visibly worse than plain English. The ARB is complete and waiting; adding
  // Locale('ar') here is the single line that ships it once Phase C lifts the
  // coverage. The LTR languages degrade gracefully by comparison, and sit in
  // the same 31-35% band as the ten that already shipped.
  test('exposes the shipped locales in picker order', () {
    expect(kSupportedLocales, [
      const Locale('en'),
      const Locale('es'),
      // European Portuguese precedes Brazilian so a bare `pt` device locale
      // lands on Portugal's wording rather than Brazil's.
      const Locale('pt'),
      const Locale('pt', 'BR'),
      const Locale('fr'),
      const Locale('de'),
      const Locale('it'),
      const Locale('ru'),
      const Locale('hi'),
      const Locale('ja'),
      const Locale('ko'),
      const Locale('zh'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      const Locale('th'),
      const Locale('vi'),
      const Locale('tr'),
      const Locale('id'),
    ]);
  });

  test('Arabic is translated but deliberately not offered yet', () {
    expect(kSupportedLocales.map((l) => l.languageCode), isNot(contains('ar')),
        reason: '35% coverage inside an RTL layout reads worse than English');
    // The name exists so listing it later is one line, not two.
    expect(displayNameOf(const Locale('ar')), 'العربية');
  });

  test('every locale has a non-empty display name', () {
    for (final locale in kSupportedLocales) {
      expect(displayNameOf(locale), isNotEmpty);
    }
  });

  test('display names are in the language itself', () {
    expect(displayNameOf(const Locale('es')), 'Español');
    expect(displayNameOf(const Locale('pt')), 'Português (Portugal)');
    expect(displayNameOf(const Locale('pt', 'BR')), 'Português (Brasil)');
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
    // With both scripts shipped, a bare '中文' no longer says which one.
    expect(displayNameOf(const Locale('zh')), '简体中文');
    expect(
        displayNameOf(Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')),
        '繁體中文');
  });
}
