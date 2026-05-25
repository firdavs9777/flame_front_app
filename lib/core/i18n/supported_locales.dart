import 'package:flutter/widgets.dart';

/// The complete list of locales the app ships with. Order matters — this is
/// the order users see in the Settings language picker.
const List<Locale> kSupportedLocales = [
  Locale('en'),
  Locale('es'),
  Locale('pt', 'BR'),
  Locale('fr'),
  Locale('de'),
  Locale('ru'),
];

/// Human-readable name of [locale] in the language itself. A Spanish speaker
/// recognizes "Español" but might not recognize "Spanish".
String displayNameOf(Locale locale) {
  switch (locale.toLanguageTag()) {
    case 'en':
      return 'English';
    case 'es':
      return 'Español';
    case 'pt-BR':
      return 'Português (Brasil)';
    case 'fr':
      return 'Français';
    case 'de':
      return 'Deutsch';
    case 'ru':
      return 'Русский';
    default:
      return locale.toLanguageTag();
  }
}
