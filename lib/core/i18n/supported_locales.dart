import 'package:flutter/widgets.dart';

/// The complete list of locales the app ships with. Order matters — this is
/// the order users see in the Settings language picker, and [resolveLocale]
/// walks it in order when it has to fall back by language code.
///
/// English first, then alphabetical by English name.
const List<Locale> kSupportedLocales = [
  Locale('en'),
  // Arabic shipped once Phase D raised it from 35% to full coverage. It is
  // right-to-left; see rtl_layout_test.
  Locale('ar'),
  Locale('bn'),
  Locale('ca'),
  Locale('zh'),
  // Traditional is a different SCRIPT, not a regional spelling: a Traditional
  // reader cannot comfortably read Simplified. locale_resolver routes zh-TW,
  // zh-HK and an explicit Hant tag here.
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  Locale('hr'),
  Locale('cs'),
  Locale('da'),
  Locale('nl'),
  // The English variants override only what genuinely differs (see
  // app_en_GB.arb — two strings). They exist so en-GB/en-AU/en-CA devices
  // resolve exactly instead of falling back, and so the stores list those
  // markets as localized.
  Locale('en', 'AU'),
  Locale('en', 'CA'),
  Locale('en', 'GB'),
  Locale('fi'),
  Locale('fr'),
  Locale('fr', 'CA'),
  Locale('de'),
  Locale('hi'),
  Locale('id'),
  Locale('it'),
  Locale('ja'),
  Locale('ko'),
  Locale('nb'),
  Locale('pt', 'BR'),
  // European Portuguese. app_pt.arb shipped from the start but was never listed
  // here, so it could not be reached and every Portugal user read Brazilian.
  Locale('pt'),
  Locale('ru'),
  Locale('es', 'MX'),
  Locale('es'),
  Locale('th'),
  Locale('tr'),
  // Urdu is right-to-left, like Arabic.
  Locale('ur'),
  Locale('vi'),
];

/// Human-readable name of [locale] in the language itself. A Spanish speaker
/// recognizes "Español" but might not recognize "Spanish".
String displayNameOf(Locale locale) {
  switch (locale.toLanguageTag()) {
    // Named with their region now that regional variants ship alongside them —
    // a bare "English" or "Español" no longer says which one.
    case 'en':
      return 'English (US)';
    case 'en-AU':
      return 'English (Australia)';
    case 'en-CA':
      return 'English (Canada)';
    case 'en-GB':
      return 'English (UK)';
    case 'es':
      return 'Español (España)';
    case 'es-MX':
      return 'Español (México)';
    case 'pt':
      return 'Português (Portugal)';
    case 'pt-BR':
      return 'Português (Brasil)';
    case 'fr':
      return 'Français (France)';
    case 'fr-CA':
      return 'Français (Canada)';
    case 'zh':
      return '简体中文';
    case 'zh-Hant':
      return '繁體中文';
    case 'ar':
      return 'العربية';
    case 'bn':
      return 'বাংলা';
    case 'ca':
      return 'Català';
    case 'cs':
      return 'Čeština';
    case 'da':
      return 'Dansk';
    case 'de':
      return 'Deutsch';
    case 'fi':
      return 'Suomi';
    case 'hi':
      return 'हिन्दी';
    case 'hr':
      return 'Hrvatski';
    case 'id':
      return 'Bahasa Indonesia';
    case 'it':
      return 'Italiano';
    case 'ja':
      return '日本語';
    case 'ko':
      return '한국어';
    case 'nb':
      return 'Norsk bokmål';
    case 'nl':
      return 'Nederlands';
    case 'ru':
      return 'Русский';
    case 'th':
      return 'ไทย';
    case 'tr':
      return 'Türkçe';
    case 'ur':
      return 'اردو';
    case 'vi':
      return 'Tiếng Việt';
    default:
      return locale.toLanguageTag();
  }
}
