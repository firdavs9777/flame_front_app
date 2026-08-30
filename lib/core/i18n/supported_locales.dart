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
  Locale('ru'),
  Locale('ja'),
  Locale('ko'),
  Locale('zh'),
  Locale('tr'),
  Locale('id'),
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
      return '中文';
    case 'tr':
      return 'Türkçe';
    case 'id':
      return 'Bahasa Indonesia';
    default:
      return locale.toLanguageTag();
  }
}
