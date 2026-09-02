/// Flag emoji per language, MIRRORED from BananaTalk's
/// lib/utils/language_flags.dart so the two products never disagree about
/// what 한국어 looks like in a list.
///
/// Flags mark countries, not languages, which is a real objection — but this
/// map handles it about as well as it can be: 🇬🇧 for `en` rather than 🇺🇸,
/// regional variants so en-us and en-gb are distinct, reasoning recorded for
/// the contested ones, and 🌐 rather than a guess for anything unresolved.
class LanguageFlags {
  static const Map<String, String> flags = {
    // Region-specific overrides. Backend uses hyphenated codes like
    // 'zh-CN', 'zh-TW', 'pt-BR' that should map to distinct flags. Listed
    // first so they win over the base-code fallback below.
    'zh-cn': '🇨🇳', // Chinese (Simplified) — Mainland
    'zh-tw': '🇹🇼', // Chinese (Traditional) — Taiwan
    'zh-hk': '🇭🇰', // Chinese (Cantonese) — Hong Kong
    'pt-br': '🇧🇷', // Portuguese (Brazil)
    'pt-pt': '🇵🇹', // Portuguese (Portugal)
    'en-us': '🇺🇸', // English (US)
    'en-gb': '🇬🇧', // English (UK)
    'en-au': '🇦🇺', // English (Australia)
    'en-ca': '🇨🇦', // English (Canada)
    'es-mx': '🇲🇽', // Spanish (Mexico)
    'es-es': '🇪🇸', // Spanish (Spain)
    'es-ar': '🇦🇷', // Spanish (Argentina)
    'fr-ca': '🇨🇦', // French (Canada)
    'fa-tj': '🇹🇯', // Tajik written as Persian-Tajikistan variant
    // Arabic varieties (catalog codes ar-EG/ar-LV/ar-GU/ar-MA — pragmatic
    // region-style tags, see backend seeds/languages.js). Explicit entries
    // required: the hyphen fallback would otherwise collapse them all to
    // 'ar' → 🇸🇦. Levantine → 🇱🇧 (recognized media standard for a
    // dialect spanning LB/SY/JO/PS); Gulf → 🇸🇦 (largest Gulf state).
    'ar-eg': '🇪🇬', // Arabic (Egyptian)
    'ar-lv': '🇱🇧', // Arabic (Levantine)
    'ar-gu': '🇸🇦', // Arabic (Gulf)
    'ar-ma': '🇲🇦', // Arabic (Moroccan Darija)

    // Major Languages
    'en': '🇬🇧', // English
    'es': '🇪🇸', // Spanish
    'fr': '🇫🇷', // French
    'de': '🇩🇪', // German
    'it': '🇮🇹', // Italian
    'pt': '🇵🇹', // Portuguese
    'ru': '🇷🇺', // Russian
    'zh': '🇨🇳', // Chinese
    'ja': '🇯🇵', // Japanese
    'ko': '🇰🇷', // Korean
    'ar': '🇸🇦', // Arabic
    'hi': '🇮🇳', // Hindi
    'nl': '🇳🇱', // Dutch
    'tr': '🇹🇷', // Turkish
    'pl': '🇵🇱', // Polish
    'sv': '🇸🇪', // Swedish
    'da': '🇩🇰', // Danish
    'no': '🇳🇴', // Norwegian
    'fi': '🇫🇮', // Finnish
    'cs': '🇨🇿', // Czech
    'el': '🇬🇷', // Greek
    'he': '🇮🇱', // Hebrew
    'th': '🇹🇭', // Thai
    'vi': '🇻🇳', // Vietnamese
    'id': '🇮🇩', // Indonesian
    'ms': '🇲🇾', // Malay
    'uk': '🇺🇦', // Ukrainian
    'ro': '🇷🇴', // Romanian
    'hu': '🇭🇺', // Hungarian
    'bg': '🇧🇬', // Bulgarian
    'hr': '🇭🇷', // Croatian
    'sr': '🇷🇸', // Serbian
    'sk': '🇸🇰', // Slovak
    'sl': '🇸🇮', // Slovene

    // African Languages
    'af': '🇿🇦', // Afrikaans
    'am': '🇪🇹', // Amharic
    'ha': '🇳🇬', // Hausa
    'ig': '🇳🇬', // Igbo
    'sw': '🇰🇪', // Swahili
    'so': '🇸🇴', // Somali
    'yo': '🇳🇬', // Yoruba
    'zu': '🇿🇦', // Zulu
    'xh': '🇿🇦', // Xhosa
    'st': '🇿🇦', // Southern Sotho
    'tn': '🇧🇼', // Tswana
    'sn': '🇿🇼', // Shona
    'rw': '🇷🇼', // Kinyarwanda
    'lg': '🇺🇬', // Luganda
    'wo': '🇸🇳', // Wolof

    // Asian Languages
    'bn': '🇧🇩', // Bengali
    'ta': '🇮🇳', // Tamil
    'te': '🇮🇳', // Telugu
    'ur': '🇵🇰', // Urdu
    'fa': '🇮🇷', // Persian/Farsi
    'ps': '🇦🇫', // Pashto
    'ku': '🇮🇶', // Kurdish
    'gu': '🇮🇳', // Gujarati
    'kn': '🇮🇳', // Kannada
    'ml': '🇮🇳', // Malayalam
    'mr': '🇮🇳', // Marathi
    'pa': '🇮🇳', // Punjabi
    'si': '🇱🇰', // Sinhala
    'ne': '🇳🇵', // Nepali
    'my': '🇲🇲', // Burmese
    'km': '🇰🇭', // Khmer
    'lo': '🇱🇦', // Lao
    'ka': '🇬🇪', // Georgian
    'hy': '🇦🇲', // Armenian
    'az': '🇦🇿', // Azerbaijani
    'uz': '🇺🇿', // Uzbek
    'kk': '🇰🇿', // Kazakh
    'ky': '🇰🇬', // Kyrgyz
    'tg': '🇹🇯', // Tajik
    'tk': '🇹🇲', // Turkmen
    'mn': '🇲🇳', // Mongolian

    // European Languages
    'sq': '🇦🇱', // Albanian
    'be': '🇧🇾', // Belarusian
    'bs': '🇧🇦', // Bosnian
    'ca': '🇪🇸', // Catalan
    'et': '🇪🇪', // Estonian
    'gl': '🇪🇸', // Galician
    'is': '🇮🇸', // Icelandic
    'ga': '🇮🇪', // Irish
    'lv': '🇱🇻', // Latvian
    'lt': '🇱🇹', // Lithuanian
    'lb': '🇱🇺', // Luxembourgish
    'mk': '🇲🇰', // Macedonian
    'mt': '🇲🇹', // Maltese
    'eu': '🇪🇸', // Basque
    'cy': '🇬🇧', // Welsh
    'gd': '🇬🇧', // Scottish Gaelic
    'br': '🇫🇷', // Breton
    'co': '🇫🇷', // Corsican
    'fy': '🇳🇱', // Western Frisian
    'fo': '🇫🇴', // Faroese

    // Pacific Languages
    'tl': '🇵🇭', // Tagalog
    'tajik': '🇹🇯', // Tajik (duplicate flag entry)
    'ceb': '🇵🇭', // Cebuano
    'haw': '🇺🇸', // Hawaiian
    'mi': '🇳🇿', // Maori
    'sm': '🇼🇸', // Samoan
    'to': '🇹🇴', // Tongan
    'fj': '🇫🇯', // Fijian

    // Middle Eastern Languages
    'iw': '🇮🇱', // Hebrew (alternative code)
    'yi': '🇮🇱', // Yiddish
    'sd': '🇵🇰', // Sindhi
    'ug': '🇨🇳', // Uyghur
    'ks': '🇮🇳', // Kashmiri
    'prs': '🇦🇫', // Dari

    // Sign languages (backend `languages` collection; flag matches
    // seeds/languages.js — the sign-language hand, not a country flag)
    'fil': '🇵🇭', // Filipino (backend code variant of Tagalog)
    'ase': '🤟', // American Sign Language
    'bfi': '🤟', // British Sign Language
    'jsl': '🤟', // Japanese Sign Language
    'kvk': '🤟', // Korean Sign Language

    // Latin American Languages
    'qu': '🇵🇪', // Quechua
    'gn': '🇵🇾', // Guarani
    'ay': '🇧🇴', // Aymara
    'ht': '🇭🇹', // Haitian Creole

    // Other Languages
    'eo': '🌍', // Esperanto (global)
    'la': '🇻🇦', // Latin
    'sa': '🇮🇳', // Sanskrit
    'jv': '🇮🇩', // Javanese
    'su': '🇮🇩', // Sundanese
    'mg': '🇲🇬', // Malagasy
    'ny': '🇲🇼', // Chichewa
    'ti': '🇪🇷', // Tigrinya
    'om': '🇪🇹', // Oromo
    'or': '🇮🇳', // Oriya
    'as': '🇮🇳', // Assamese
    'bh': '🇮🇳', // Bihari
    'dv': '🇲🇻', // Divehi
    'rn': '🇧🇮', // Kirundi
    'sg': '🇨🇫', // Sango
    'tt': '🇷🇺', // Tatar
    'bo': '🇨🇳', // Tibetan
    'ts': '🇿🇦', // Tsonga
    've': '🇿🇦', // Venda
    'ss': '🇸🇿', // Swati
    'ee': '🇬🇭', // Ewe
    'tw': '🇬🇭', // Twi
    'ak': '🇬🇭', // Akan
    'ln': '🇨🇩', // Lingala
    'kg': '🇨🇩', // Kongo
    'lu': '🇨🇩', // Luba-Katanga

    // Less common languages
    'aa': '🇪🇹', // Afar
    'ab': '🇬🇪', // Abkhaz
    'ae': '🌍', // Avestan
    'av': '🇷🇺', // Avaric
    'ba': '🇷🇺', // Bashkir
    'bi': '🇻🇺', // Bislama
    'bm': '🇲🇱', // Bambara
    'ce': '🇷🇺', // Chechen
    'ch': '🇬🇺', // Chamorro
    'cr': '🇨🇦', // Cree
    'cv': '🇷🇺', // Chuvash
    'ff': '🇳🇬', // Fulah
    'gv': '🇮🇲', // Manx
    'ho': '🇵🇬', // Hiri Motu
    'hz': '🇳🇦', // Herero
    'ia': '🌍', // Interlingua
    'ie': '🌍', // Interlingue
    'ii': '🇨🇳', // Sichuan Yi
    'ik': '🇺🇸', // Inupiaq
    'io': '🌍', // Ido
    'iu': '🇨🇦', // Inuktitut
    'kj': '🇳🇦', // Kuanyama
    'kl': '🇬🇱', // Kalaallisut
    'kr': '🇳🇬', // Kanuri
    'kv': '🇷🇺', // Komi
    'kw': '🇬🇧', // Cornish
    'mh': '🇲🇭', // Marshallese
    'na': '🇳🇷', // Nauru
    'nd': '🇿🇼', // North Ndebele
    'ng': '🇳🇦', // Ndonga
    'nv': '🇺🇸', // Navajo
    'oc': '🇫🇷', // Occitan
    'oj': '🇨🇦', // Ojibwe
    'os': '🇷🇺', // Ossetian
    'pi': '🇮🇳', // Pali
    'rm': '🇨🇭', // Romansh
    'sc': '🇮🇹', // Sardinian
    'se': '🇳🇴', // Northern Sami
    'ty': '🇵🇫', // Tahitian
    'vo': '🌍', // Volapük
    'wa': '🇧🇪', // Walloon
    'za': '🇨🇳', // Zhuang
  };

  /// Get flag emoji for a language code.
  ///
  /// Lookup order:
  ///   1. Exact match on the full code (handles region overrides like
  ///      'zh-tw' → 🇹🇼 differently from 'zh-cn' → 🇨🇳).
  ///   2. Base-code fallback (strip the region suffix). Critical for the
  ///      backend's hyphenated codes — e.g. 'fr-ca' falls through to 'fr'
  ///      if no Canada-specific override exists.
  ///   3. Globe emoji 🌐 if neither resolves.
  static String getFlag(String languageCode) {
    if (languageCode.isEmpty) return '🌐';
    final lower = languageCode.toLowerCase();
    final direct = flags[lower];
    if (direct != null) return direct;
    final hyphen = lower.indexOf('-');
    if (hyphen > 0) {
      final base = flags[lower.substring(0, hyphen)];
      if (base != null) return base;
    }
    return '🌐';
  }
}
