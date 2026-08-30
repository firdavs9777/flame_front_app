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
        const Locale('is'),  // unsupported (Italian ships since Phase B)
        const Locale('mt'),  // unsupported (Dutch ships since Phase D, so the
                             // old 'nl' entry stopped being a miss)
        const Locale('de'),  // supported — should win
      ],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('de'));
  });

  // fr-CA ships since Phase D, so it now matches exactly and no longer
  // exercises this path. fr-BE does: French we have no regional ARB for.
  test('unsupported locale with country falls back to bare language', () {
    final result = resolveLocale(
      saved: null,
      deviceLocales: [const Locale('fr', 'BE')],
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
      deviceLocales: [const Locale('is')],
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
      saved: const Locale('is'),
      deviceLocales: [const Locale('es')],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('es'));
  });
}
