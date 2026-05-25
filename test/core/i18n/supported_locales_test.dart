import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flame/core/i18n/supported_locales.dart';

void main() {
  test('exposes exactly six locales in expected order', () {
    expect(kSupportedLocales, [
      const Locale('en'),
      const Locale('es'),
      const Locale('pt', 'BR'),
      const Locale('fr'),
      const Locale('de'),
      const Locale('ru'),
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
  });
}
