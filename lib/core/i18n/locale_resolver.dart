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

  // 2. Device locales — exact match preferred
  for (final device in deviceLocales) {
    for (final s in supported) {
      if (s == device) return s;
    }
  }

  // 3. Device locales — language code match
  for (final device in deviceLocales) {
    for (final s in supported) {
      if (s.languageCode == device.languageCode) return s;
    }
  }

  // 4. Hard fallback
  return const Locale('en');
}

Locale? _findMatch(Locale candidate, List<Locale> supported) {
  for (final s in supported) {
    if (s == candidate) return s;
  }
  for (final s in supported) {
    if (s.languageCode == candidate.languageCode) return s;
  }
  return null;
}
