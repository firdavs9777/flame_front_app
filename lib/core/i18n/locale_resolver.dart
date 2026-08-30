import 'package:flutter/widgets.dart';

/// Pure resolution of which [Locale] the app should display.
///
/// Resolution chain (top wins):
///   1. [saved] preference (from SharedPreferences) — if supported
///   2. First entry in [deviceLocales] that matches a supported locale exactly
///   3. First entry in [deviceLocales] whose language code (ignoring country)
///      matches a supported locale's language code
///   4. English ('en') as the hard fallback
Locale resolveLocale({
  required Locale? saved,
  required List<Locale> deviceLocales,
  required List<Locale> supported,
}) {
  // 1. Saved preference — exact or language-code match
  if (saved != null) {
    final match = _findMatch(saved, supported);
    if (match != null) return match;
  }

  // 2. Device locales — exact match preferred. Run across EVERY device locale
  // before falling back, so an exact hit on the user's second choice beats an
  // approximate hit on their first.
  for (final device in deviceLocales) {
    for (final s in supported) {
      if (s == device) return s;
    }
  }

  // 3. Device locales — language match, honouring script
  for (final device in deviceLocales) {
    final match = _languageMatch(device, supported);
    if (match != null) return match;
  }

  // 4. Hard fallback
  return const Locale('en');
}

/// Regions that write Chinese in Traditional characters.
const _kTraditionalChineseRegions = {'TW', 'HK', 'MO'};

/// Whether [locale] asks for Traditional Chinese, by explicit script tag or by
/// region. A Traditional reader cannot comfortably read Simplified, so this is
/// a real distinction rather than a cosmetic one — unlike en-GB vs en-US.
bool _wantsTraditionalChinese(Locale locale) =>
    locale.languageCode == 'zh' &&
    (locale.scriptCode == 'Hant' ||
        _kTraditionalChineseRegions.contains(locale.countryCode));

Locale? _findMatch(Locale candidate, List<Locale> supported) {
  for (final s in supported) {
    if (s == candidate) return s;
  }
  return _languageMatch(candidate, supported);
}

/// Best same-language match for [candidate], preferring one written in the same
/// script.
Locale? _languageMatch(Locale candidate, List<Locale> supported) {
  final wantsHant = _wantsTraditionalChinese(candidate);

  // Same language AND the script the candidate actually reads.
  //
  // The country-less locale wins over any regional variant. Picker order is a
  // product decision — it lists Portuguese (Brazil) before Portuguese
  // (Portugal), Spanish (Mexico) before Spanish (Spain) — and resolution must
  // not inherit it. Taking the first match by position is what once sent every
  // Portugal user to Brazilian wording; pt-PT must land on pt, and es-ES on
  // es, no matter how the picker is sorted. An exact match is handled by the
  // caller before this runs, so es-MX still gets es-MX.
  Locale? regional;
  for (final s in supported) {
    if (s.languageCode != candidate.languageCode) continue;
    if (candidate.languageCode == 'zh' &&
        (s.scriptCode == 'Hant') != wantsHant) {
      continue;
    }
    if (s.countryCode == null) return s;
    regional ??= s;
  }
  if (regional != null) return regional;

  // Same language, wrong script. Only reachable for Chinese, and only while one
  // of the two scripts is unshipped: Simplified is closer for a Traditional
  // reader than English is.
  for (final s in supported) {
    if (s.languageCode == candidate.languageCode) return s;
  }
  return null;
}
