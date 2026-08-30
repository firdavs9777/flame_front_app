import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/locale_resolver.dart';
import 'package:flame/core/i18n/supported_locales.dart';

// The store listing enumerates region variants the resolver has to answer for:
// English (U.K./Australia/Canada), Spanish (Spain/Mexico), Portuguese
// (Portugal/Brazil), Chinese (Simplified/Traditional), French (Canada).
//
// Matching on language code alone answers most of them correctly and cheaply —
// en-GB wants English, and shipping a near-identical en-GB ARB to say "colour"
// would be cost with no benefit. Two cases it gets WRONG, though, because the
// script or the wording genuinely differs:
//
//   pt-PT was resolving to Brazilian Portuguese. app_pt.arb (European) existed
//   the whole time but was never listed in kSupportedLocales, so it could not
//   be reached and a Portugal user read Brazilian.
//
//   zh-TW/zh-HK resolve to Simplified, which a Traditional reader cannot read
//   comfortably. Traditional is not shipped yet, so Simplified stays the
//   fallback for now — but the resolver prefers Hant the moment it exists,
//   rather than needing this logic rewritten later.

Locale _resolve(Locale device, {List<Locale>? supported}) => resolveLocale(
      saved: null,
      deviceLocales: [device],
      supported: supported ?? kSupportedLocales,
    );

void main() {
  group('English variants', () {
    // These used to fall back to plain en, on the reasoning that they needed no
    // ARB of their own. Phase D ships them: each overrides only what genuinely
    // differs (en-GB has two strings — "Licences" and "Films"), which is enough
    // to resolve exactly and to list the market as localized.
    test('en-GB, en-AU and en-CA resolve to themselves', () {
      for (final region in ['GB', 'AU', 'CA']) {
        expect(_resolve(Locale('en', region)), Locale('en', region));
      }
    });

    test('an English region we do not ship still falls back to en', () {
      expect(_resolve(const Locale('en', 'NZ')), const Locale('en'));
      expect(_resolve(const Locale('en', 'IE')), const Locale('en'));
    });
  });

  group('Spanish and French variants', () {
    test('es-MX resolves to Mexican Spanish, es-ES to Peninsular', () {
      expect(_resolve(const Locale('es', 'MX')), const Locale('es', 'MX'));
      expect(_resolve(const Locale('es', 'ES')), const Locale('es'));
    });

    // The picker lists Spanish (Mexico) before Spain, so resolving by list
    // position would hand Spain the Mexican wording. The country-less locale
    // wins the language fallback precisely so ordering cannot do that.
    test('a Spanish region we do not ship falls back to es, not es-MX', () {
      expect(_resolve(const Locale('es', 'AR')), const Locale('es'));
      expect(_resolve(const Locale('es', 'CO')), const Locale('es'));
    });

    test('fr-CA resolves to Canadian French', () {
      expect(_resolve(const Locale('fr', 'CA')), const Locale('fr', 'CA'));
    });

    test('a French region we do not ship falls back to fr, not fr-CA', () {
      expect(_resolve(const Locale('fr', 'BE')), const Locale('fr'));
      expect(_resolve(const Locale('fr', 'CH')), const Locale('fr'));
    });
  });

  group('Portuguese distinguishes Portugal from Brazil', () {
    test('pt-PT resolves to European Portuguese, not Brazilian', () {
      expect(_resolve(const Locale('pt', 'PT')), const Locale('pt'));
    });

    test('bare pt resolves to European Portuguese', () {
      expect(_resolve(const Locale('pt')), const Locale('pt'));
    });

    test('pt-BR still resolves to Brazilian', () {
      expect(_resolve(const Locale('pt', 'BR')), const Locale('pt', 'BR'));
    });
  });

  group('Chinese distinguishes script, not just language', () {
    final hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');

    test('zh-TW and zh-HK prefer Traditional when it is shipped', () {
      final supported = [...kSupportedLocales, hant];
      expect(_resolve(const Locale('zh', 'TW'), supported: supported), hant);
      expect(_resolve(const Locale('zh', 'HK'), supported: supported), hant);
    });

    test('an explicit Hant script tag prefers Traditional', () {
      final supported = [...kSupportedLocales, hant];
      expect(_resolve(hant, supported: supported), hant);
    });

    test('zh-CN and zh-SG stay Simplified even when Traditional is shipped', () {
      final supported = [...kSupportedLocales, hant];
      expect(_resolve(const Locale('zh', 'CN'), supported: supported),
          const Locale('zh'));
      expect(_resolve(const Locale('zh', 'SG'), supported: supported),
          const Locale('zh'));
    });

    test('zh-TW falls back to Simplified only when Hant is absent', () {
      // Phase B shipped Hant, so the live list now answers zh-TW correctly.
      // The degraded path still has to work — Simplified is closer for a
      // Traditional reader than English — so it is pinned against a list that
      // omits Hant rather than deleted along with the compromise.
      const noHant = [Locale('en'), Locale('zh')];
      expect(_resolve(const Locale('zh', 'TW'), supported: noHant),
          const Locale('zh'));
      expect(_resolve(const Locale('zh', 'TW')), hant,
          reason: 'the shipped list has Traditional now');
    });
  });

  group('right-to-left locales', () {
    // Both were held back while coverage was low — an RTL page two thirds full
    // of LTR English is worse than plain English. Phase D closed that gap.
    test('Arabic and Urdu resolve to themselves now that they ship', () {
      expect(_resolve(const Locale('ar')), const Locale('ar'));
      expect(_resolve(const Locale('ur')), const Locale('ur'));
      expect(_resolve(const Locale('ar', 'EG')), const Locale('ar'));
      expect(_resolve(const Locale('ur', 'PK')), const Locale('ur'));
    });
  });

  group('a language we ship nothing for', () {
    test('falls back to English', () {
      expect(_resolve(const Locale('is')), const Locale('en'));
      expect(_resolve(const Locale('mt')), const Locale('en'));
    });
  });
}
