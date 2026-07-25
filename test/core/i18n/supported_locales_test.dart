import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flame/core/i18n/supported_locales.dart';

void main() {
  test('exposes exactly eleven locales in expected order', () {
    expect(kSupportedLocales, [
      const Locale('en'),
      const Locale('es'),
      const Locale('pt', 'BR'),
      const Locale('fr'),
      const Locale('de'),
      const Locale('ru'),
      const Locale('ja'),
      const Locale('ko'),
      const Locale('zh'),
      const Locale('tr'),
      const Locale('id'),
    ]);
  });

  test('every locale has a non-empty display name', () {
    for (final locale in kSupportedLocales) {
      expect(displayNameOf(locale), isNotEmpty);
    }
  });

  test('display names are in the language itself', () {
    expect(displayNameOf(const Locale('es')), 'Español');
    expect(displayNameOf(const Locale('pt', 'BR')), 'Português (Brasil)');
    expect(displayNameOf(const Locale('de')), 'Deutsch');
    expect(displayNameOf(const Locale('ru')), 'Русский');
    expect(displayNameOf(const Locale('ja')), '日本語');
    expect(displayNameOf(const Locale('ko')), '한국어');
    expect(displayNameOf(const Locale('zh')), '中文');
    expect(displayNameOf(const Locale('tr')), 'Türkçe');
    expect(displayNameOf(const Locale('id')), 'Bahasa Indonesia');
  });
}
