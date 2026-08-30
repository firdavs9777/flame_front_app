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
  group('English variants fall back to English', () {
    test('en-GB, en-AU and en-CA all resolve to en', () {
      for (final region in ['GB', 'AU', 'CA']) {
        expect(_resolve(Locale('en', region)), const Locale('en'),
            reason: 'en-$region needs no ARB of its own');
      }
    });
  });

  group('Spanish and French variants fall back to their language', () {
    test('es-MX and es-ES resolve to es', () {
      expect(_resolve(const Locale('es', 'MX')), const Locale('es'));
      expect(_resolve(const Locale('es', 'ES')), const Locale('es'));
    });

    test('fr-CA resolves to fr', () {
      expect(_resolve(const Locale('fr', 'CA')), const Locale('fr'));
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

  group('locales with no translation yet', () {
    test('Arabic and Urdu resolve to English until they ship', () {
      expect(_resolve(const Locale('ar')), const Locale('en'));
      expect(_resolve(const Locale('ur')), const Locale('en'));
    });
  });
}
