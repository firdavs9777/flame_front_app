import 'package:flutter/widgets.dart';

/// The complete list of locales the app ships with. Order matters — this is
/// the order users see in the Settings language picker.
const List<Locale> kSupportedLocales = [
  Locale('en'),
  Locale('es'),
  // European Portuguese. app_pt.arb shipped from the start but was never listed
  // here, so it could not be reached and every Portugal user read Brazilian.
  Locale('pt'),
  Locale('pt', 'BR'),
  Locale('fr'),
  Locale('de'),
  Locale('it'),
  Locale('ru'),
  Locale('hi'),
  Locale('ja'),
  Locale('ko'),
  Locale('zh'),
  // Traditional is a different SCRIPT, not a regional spelling: a Traditional
  // reader cannot comfortably read Simplified. locale_resolver routes zh-TW,
  // zh-HK and an explicit Hant tag here.
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  Locale('th'),
  Locale('vi'),
  Locale('tr'),
  Locale('id'),
  // Arabic is translated (app_ar.arb) but deliberately absent: at 35% coverage
  // inside a right-to-left layout, two thirds of the UI would be LTR English
  // inside a mirrored page — worse than plain English. Add `const Locale('ar')`
  // here to ship it once Phase C raises the coverage.
];

/// Human-readable name of [locale] in the language itself. A Spanish speaker
/// recognizes "Español" but might not recognize "Spanish".
String displayNameOf(Locale locale) {
  switch (locale.toLanguageTag()) {
    case 'en':
      return 'English';
    case 'es':
      return 'Español';
    case 'pt':
      return 'Português (Portugal)';
    case 'pt-BR':
      return 'Português (Brasil)';
    case 'fr':
      return 'Français';
    case 'de':
      return 'Deutsch';
    case 'ru':
      return 'Русский';
    case 'ja':
      return '日本語';
    case 'ko':
      return '한국어';
    case 'zh':
      // Both scripts ship now, so a bare '中文' no longer says which one.
      return '简体中文';
    case 'zh-Hant':
      return '繁體中文';
    case 'it':
      return 'Italiano';
    case 'hi':
      return 'हिन्दी';
    case 'th':
      return 'ไทย';
    case 'vi':
      return 'Tiếng Việt';
    // Named ahead of being listed in kSupportedLocales, so shipping Arabic is
    // one line there rather than two edits.
    case 'ar':
      return 'العربية';
    case 'tr':
      return 'Türkçe';
    case 'id':
      return 'Bahasa Indonesia';
    default:
      return locale.toLanguageTag();
  }
}
