import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/core/i18n/locale_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('initial state is null until initialize() is called', () {
    final container = ProviderContainer();
    expect(container.read(localeProvider), isNull);
  });

  test('initialize resolves to device locale when no preference saved', () async {
    final container = ProviderContainer();
    await container.read(localeProvider.notifier).initialize(
      deviceLocales: [const Locale('es')],
    );
    expect(container.read(localeProvider), const Locale('es'));
  });

  test('initialize honors saved preference', () async {
    SharedPreferences.setMockInitialValues({'preferred_locale': 'fr'});
    final container = ProviderContainer();
    await container.read(localeProvider.notifier).initialize(
      deviceLocales: [const Locale('es')],
    );
    expect(container.read(localeProvider), const Locale('fr'));
  });

  test('setLocale updates state and persists', () async {
    final container = ProviderContainer();
    await container.read(localeProvider.notifier).initialize(
      deviceLocales: [const Locale('en')],
    );
    await container.read(localeProvider.notifier).setLocale(const Locale('de'));

    expect(container.read(localeProvider), const Locale('de'));

    // Re-initialize a fresh container — should pick up the persisted choice
    final container2 = ProviderContainer();
    await container2.read(localeProvider.notifier).initialize(
      deviceLocales: [const Locale('en')],
    );
    expect(container2.read(localeProvider), const Locale('de'));
  });

  test('clearLocale removes preference and reverts to device locale', () async {
    final container = ProviderContainer();
    await container.read(localeProvider.notifier).initialize(
      deviceLocales: [const Locale('es')],
    );
    await container.read(localeProvider.notifier).setLocale(const Locale('de'));
    await container.read(localeProvider.notifier).clearLocale(
      deviceLocales: [const Locale('es')],
    );

    expect(container.read(localeProvider), const Locale('es'));
  });
}
