import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/core/i18n/locale_storage.dart';

void main() {
  late LocaleStorage storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = LocaleStorage();
  });

  test('read returns null when nothing saved', () async {
    expect(await storage.read(), isNull);
  });

  test('write then read round-trips a simple locale', () async {
    await storage.write(const Locale('es'));
    expect(await storage.read(), const Locale('es'));
  });

  test('write then read round-trips a locale with country code', () async {
    await storage.write(const Locale('pt', 'BR'));
    expect(await storage.read(), const Locale('pt', 'BR'));
  });

  test('clear removes the saved locale', () async {
    await storage.write(const Locale('fr'));
    await storage.clear();
    expect(await storage.read(), isNull);
  });

  test('read returns null on malformed stored value', () async {
    SharedPreferences.setMockInitialValues({'preferred_locale': 'not-a-locale-xxx-yyy-zzz'});
    storage = LocaleStorage();
    expect(await storage.read(), isNull);
  });
}
