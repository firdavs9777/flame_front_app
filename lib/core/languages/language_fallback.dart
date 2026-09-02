import 'package:flame/core/languages/language.dart';

/// Shown when the catalogue cannot be fetched AND nothing was cached — a
/// first-ever launch with no network.
///
/// Deliberately small. This is a floor so the picker is never empty, NOT the
/// catalogue: the real list is 127+ entries from the server. Mirrors the size
/// and intent of BananaTalk's kLanguageCatalogFallback.
const List<Language> kLanguageFallback = [
  Language(code: 'en', name: 'English', nativeName: 'English'),
  Language(code: 'ko', name: 'Korean', nativeName: '한국어'),
  Language(code: 'ja', name: 'Japanese', nativeName: '日本語'),
  Language(code: 'zh', name: 'Chinese', nativeName: '中文'),
  Language(code: 'es', name: 'Spanish', nativeName: 'Español'),
  Language(code: 'fr', name: 'French', nativeName: 'Français'),
  Language(code: 'de', name: 'German', nativeName: 'Deutsch'),
  Language(code: 'it', name: 'Italian', nativeName: 'Italiano'),
  Language(code: 'pt', name: 'Portuguese', nativeName: 'Português'),
  Language(code: 'ru', name: 'Russian', nativeName: 'Русский'),
  Language(code: 'ar', name: 'Arabic', nativeName: 'العربية'),
  Language(code: 'hi', name: 'Hindi', nativeName: 'हिन्दी'),
  Language(code: 'th', name: 'Thai', nativeName: 'ไทย'),
  Language(code: 'vi', name: 'Vietnamese', nativeName: 'Tiếng Việt'),
  Language(code: 'id', name: 'Indonesian', nativeName: 'Bahasa Indonesia'),
  Language(code: 'tr', name: 'Turkish', nativeName: 'Türkçe'),
  Language(code: 'nl', name: 'Dutch', nativeName: 'Nederlands'),
];

/// Surfaced above the alphabetical list in the picker. The same ten
/// BananaTalk recommends, so a user of both apps sees a consistent shortlist.
const List<String> kRecommendedCodes = [
  'en', 'ko', 'ja', 'zh', 'es', 'fr', 'de', 'it', 'pt', 'ru',
];
