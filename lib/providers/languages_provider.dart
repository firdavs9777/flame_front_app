import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flame/core/languages/language.dart';
import 'package:flame/core/languages/language_fallback.dart';
import 'package:flame/services/api_client.dart';

const String kLanguagesCacheKey = 'flame_languages_catalog_v1';

/// The language catalogue — the ONE source for every picker.
///
/// Resolution order, mirroring BananaTalk's languages_provider.dart:
///
///   1. network fetch, persisted for next time
///   2. the persisted copy from a previous session
///   3. [kLanguageFallback], a small bundled list
///
/// The layering is what makes it safe to put a fetch behind the REGISTRATION
/// screen — the screen App Review rejected. There is no path where the picker
/// is empty: worst case it is short.
List<Language> parseLanguageCatalog(String body) {
  try {
    final decoded = json.decode(body);
    final data = decoded is Map<String, dynamic>
        ? (decoded['data'] as List? ?? const [])
        : (decoded is List ? decoded : const []);

    final out = <Language>[];
    for (final entry in data) {
      if (entry is! Map<String, dynamic>) continue;
      try {
        out.add(Language.fromJson(entry));
      } catch (_) {
        // One malformed row must not cost the other 180.
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Resolves the catalogue. [fetch] and [prefs] are injected so the whole
/// ladder is testable without a network or a platform channel.
Future<List<Language>> resolveCatalog({
  required Future<String> Function() fetch,
  required SharedPreferences prefs,
}) async {
  try {
    final body = await fetch();
    final fresh = parseLanguageCatalog(body);
    if (fresh.isNotEmpty) {
      await prefs.setString(kLanguagesCacheKey, body);
      return fresh;
    }
    // A 200 carrying nothing is a failure, not an answer — fall through
    // rather than overwrite a good cache with emptiness.
  } catch (error) {
    debugPrint('languages: fetch failed — $error');
  }

  final cached = prefs.getString(kLanguagesCacheKey);
  if (cached != null) {
    final list = parseLanguageCatalog(cached);
    if (list.isNotEmpty) return list;
  }

  return kLanguageFallback;
}

final languageCatalogProvider = FutureProvider<List<Language>>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return resolveCatalog(
    prefs: prefs,
    fetch: () async {
      final res = await ApiClient().get('/languages');
      if (!res.success) throw Exception(res.error ?? 'languages fetch failed');
      return json.encode({'data': res.data});
    },
  );
});
