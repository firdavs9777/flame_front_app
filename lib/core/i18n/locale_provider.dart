import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'locale_resolver.dart';
import 'locale_storage.dart';
import 'supported_locales.dart';

/// Holds the active [Locale] the app should render in.
///
/// State is `null` until [LocaleController.initialize] has run. `main.dart`
/// must call initialize() at startup before building MaterialApp.
final localeProvider =
    StateNotifierProvider<LocaleController, Locale?>((ref) => LocaleController());

class LocaleController extends StateNotifier<Locale?> {
  LocaleController({LocaleStorage? storage})
      : _storage = storage ?? LocaleStorage(),
        super(null);

  final LocaleStorage _storage;

  /// Resolves the active locale using saved preference + device locales and
  /// publishes it as state. Must be called once at app startup.
  Future<void> initialize({required List<Locale> deviceLocales}) async {
    final saved = await _storage.read();
    state = resolveLocale(
      saved: saved,
      deviceLocales: deviceLocales,
      supported: kSupportedLocales,
    );
  }

  /// Persists [locale] as the user's preference and updates state.
  Future<void> setLocale(Locale locale) async {
    await _storage.write(locale);
    state = locale;
  }

  /// Removes the saved preference and reverts to the device locale.
  Future<void> clearLocale({required List<Locale> deviceLocales}) async {
    await _storage.clear();
    state = resolveLocale(
      saved: null,
      deviceLocales: deviceLocales,
      supported: kSupportedLocales,
    );
  }
}
