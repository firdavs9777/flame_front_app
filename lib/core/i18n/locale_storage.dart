import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's preferred locale across app launches.
///
/// Storage format: BCP 47 language tag (`en`, `es`, `pt-BR`). Stored as a
/// single string under [_key] in SharedPreferences.
class LocaleStorage {
  static const String _key = 'preferred_locale';

  Future<Locale?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final tag = prefs.getString(_key);
    if (tag == null) return null;
    return _parseTag(tag);
  }

  Future<void> write(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.toLanguageTag());
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  // Accepts: "en", "es", "pt-BR". Returns null on anything malformed.
  Locale? _parseTag(String tag) {
    final parts = tag.split('-');
    if (parts.isEmpty || parts.first.length < 2 || parts.first.length > 3) {
      return null;
    }
    if (parts.length == 1) return Locale(parts[0]);
    if (parts.length == 2) return Locale(parts[0], parts[1]);
    return null;
  }
}
