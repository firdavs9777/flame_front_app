import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flame/core/languages/language_fallback.dart';
import 'package:flame/providers/languages_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('parses a GET /languages body', () {
    final list = parseLanguageCatalog(
      '{"success":true,"data":[{"code":"ko","name":"Korean","nativeName":"한국어"}]}',
    );

    expect(list, hasLength(1));
    expect(list.first.nativeName, '한국어');
  });

  test('malformed JSON yields an empty list rather than throwing', () {
    // Resolution falls through to the cache, then the fallback. A throw here
    // would take the registration screen with it.
    expect(parseLanguageCatalog('not json'), isEmpty);
    expect(parseLanguageCatalog('{"data":"wrong shape"}'), isEmpty);
    expect(parseLanguageCatalog(''), isEmpty);
  });

  test('a malformed ENTRY is skipped, not fatal to the whole catalogue', () {
    final list = parseLanguageCatalog(
      '{"data":[{"name":"no code"},{"code":"ko","name":"Korean","nativeName":"한국어"}]}',
    );

    expect(list, hasLength(1), reason: 'one bad row must not lose the rest');
    expect(list.first.code, 'ko');
  });

  test('resolveCatalog prefers the network result and caches it', () async {
    final prefs = await SharedPreferences.getInstance();

    final list = await resolveCatalog(
      fetch: () async =>
          '{"data":[{"code":"ja","name":"Japanese","nativeName":"日本語"}]}',
      prefs: prefs,
    );

    expect(list.single.code, 'ja');
    expect(prefs.getString(kLanguagesCacheKey), isNotNull,
        reason: 'persisted so the next launch works offline');
  });

  test('falls back to the cache when the network fails', () async {
    SharedPreferences.setMockInitialValues({
      kLanguagesCacheKey:
          '{"data":[{"code":"ko","name":"Korean","nativeName":"한국어"}]}',
    });
    final prefs = await SharedPreferences.getInstance();

    final list = await resolveCatalog(
      fetch: () async => throw Exception('offline'),
      prefs: prefs,
    );

    expect(list.single.code, 'ko');
  });

  test('falls back to the bundled list when there is no cache either', () async {
    // First-ever launch, offline. The picker must still work — it is on the
    // registration screen App Review rejected, and an empty one is worse
    // than a short one.
    final prefs = await SharedPreferences.getInstance();

    final list = await resolveCatalog(
      fetch: () async => throw Exception('offline'),
      prefs: prefs,
    );

    expect(list, kLanguageFallback);
  });

  test('an empty network response does not overwrite a good cache', () async {
    SharedPreferences.setMockInitialValues({
      kLanguagesCacheKey:
          '{"data":[{"code":"ko","name":"Korean","nativeName":"한국어"}]}',
    });
    final prefs = await SharedPreferences.getInstance();

    final list = await resolveCatalog(fetch: () async => '{"data":[]}', prefs: prefs);

    expect(list.single.code, 'ko',
        reason: 'a 200 with nothing in it is a failure, not an answer');
  });
}
