import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/locale_resolver.dart';
import 'package:flame/core/i18n/supported_locales.dart';

void main() {
  test('saved preference wins over device locale', () {
    final result = resolveLocale(
      saved: const Locale('fr'),
      deviceLocales: [const Locale('es')],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('fr'));
  });

  test('device locale wins when no preference saved', () {
    final result = resolveLocale(
      saved: null,
      deviceLocales: [const Locale('es')],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('es'));
  });

  test('walks device locale list and picks first supported match', () {
    final result = resolveLocale(
      saved: null,
      deviceLocales: [
        const Locale('it'),  // unsupported
        const Locale('nl'),  // unsupported
        const Locale('de'),  // supported — should win
      ],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('de'));
  });

  test('unsupported locale with country falls back to bare language', () {
    final result = resolveLocale(
      saved: null,
      deviceLocales: [const Locale('fr', 'CA')],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('fr'));
  });

  test('pt_BR device locale matches pt_BR supported locale exactly', () {
    final result = resolveLocale(
      saved: null,
      deviceLocales: [const Locale('pt', 'BR')],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('pt', 'BR'));
  });

  // Was 'falls back to pt_BR (only Portuguese we have)'. That premise was
  // wrong: app_pt.arb — European Portuguese — shipped from the start but was
  // missing from kSupportedLocales, so it could not be reached and Portugal
  // read Brazilian wording. Listing it fixed the resolution, not this test.
  test('pt_PT device locale resolves to European Portuguese', () {
    final result = resolveLocale(
      saved: null,
      deviceLocales: [const Locale('pt', 'PT')],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('pt'));
  });

  test('unsupported language falls back to English', () {
    final result = resolveLocale(
      saved: null,
      deviceLocales: [const Locale('it')],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('en'));
  });

  test('empty device locales falls back to English', () {
    final result = resolveLocale(
      saved: null,
      deviceLocales: const [],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('en'));
  });

  test('saved preference that is unsupported is ignored', () {
    // Defensive: if a user somehow has a stale unsupported tag stored,
    // we shouldn't honor it.
    final result = resolveLocale(
      saved: const Locale('it'),
      deviceLocales: [const Locale('es')],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('es'));
  });
}
