# Localization (Phase 0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the localization infrastructure end-to-end with six languages (EN, ES, PT-BR, FR, DE, RU), translate the app-shell screens, and add a Settings language picker that syncs preference to the backend.

**Architecture:** First-party `flutter_localizations` + `gen_l10n` codegen, ARB files in `lib/l10n/`, type-safe `AppLocalizations` accessed via `context.l10n`. A Riverpod provider owns the active `Locale`; resolution follows saved-preference → device-locale → language-code → English. Settings picker writes to SharedPreferences and fires a background `PATCH /v1/users/me` with the new `preferred_language`.

**Tech Stack:** Flutter 3.x, `flutter_localizations` (SDK), `intl ^0.19.0` (already present), `shared_preferences` (already present), `flutter_riverpod` (already present).

**Scope refinement from the spec:** The spec listed "Login / register / welcome screens" for Phase 0. This plan migrates **welcome, login, settings, main_shell (bottom-nav)** plus the new language picker. Registration entry and the multi-step registration flow are inseparable in `registration_flow.dart`, so the entire registration UI moves to Phase 1 as a coherent unit. If you want registration in Phase 0 instead, add it as an extra task after Task 18.

**Flutter 3.38.7 tooling realities discovered during Task 1 (overrides spec details):**
1. `gen-l10n` **fatally errors** on a missing base locale for a regional variant. Spec said 6 ARB files; reality requires **7** — a `lib/l10n/app_pt.arb` base file alongside `app_pt_BR.arb`. The base `app_pt.arb` is kept identical to `app_pt_BR.arb` (every key + value copied) so they stay in sync. The ARB parity test in Task 20 enforces this.
2. `synthetic-package: false` is **deprecated and ignored** by gen-l10n with a warning. It is omitted from `l10n.yaml` even though the original spec listed it. `output-dir: lib/l10n/gen` alone is sufficient to produce non-synthetic output.
3. `intl` was bumped from `^0.19.0` to `^0.20.2` to satisfy `flutter_localizations` SDK pinning. Mechanical dependency-resolution upgrade.

`kSupportedLocales` (Task 2) still has **6 entries** (no bare `Locale('pt')`). Generated `AppLocalizations.supportedLocales` will have 7, but we pass our 6-entry list to `MaterialApp.supportedLocales` so the custom resolver in Task 4 still handles `pt → pt_BR` fallback as designed.

**Phase 0 file inventory:**
| File | Action | Responsibility |
|---|---|---|
| `pubspec.yaml` | modify | Add `flutter_localizations` SDK dep, set `flutter: generate: true` |
| `l10n.yaml` | create | gen_l10n config (ARB dir, template, output class) |
| `lib/l10n/app_en.arb` | create | English template with all Phase 0 keys + `@`-metadata |
| `lib/l10n/app_es.arb` | create | Spanish (initially English copy) |
| `lib/l10n/app_pt_BR.arb` | create | Portuguese (Brazil) |
| `lib/l10n/app_fr.arb` | create | French |
| `lib/l10n/app_de.arb` | create | German |
| `lib/l10n/app_ru.arb` | create | Russian |
| `lib/core/i18n/supported_locales.dart` | create | Single source of truth: list of 6 Locales |
| `lib/core/i18n/locale_storage.dart` | create | Reads/writes preferred locale to SharedPreferences |
| `lib/core/i18n/locale_resolver.dart` | create | Pure function: resolve(saved, device, supported) → Locale |
| `lib/core/i18n/locale_provider.dart` | create | Riverpod StateNotifier — current Locale + setLocale/clearLocale |
| `lib/core/i18n/build_context_ext.dart` | create | `context.l10n` extension |
| `lib/core/i18n/error_messages.dart` | create | `translateApiError(AppLocalizations, ApiResponse)` mapping |
| `lib/models/user.dart` | modify | Add nullable `preferredLanguage` field |
| `lib/services/auth_service.dart` | modify | Add `updatePreferredLanguage(String code)` |
| `lib/services/api_client.dart` | modify | Remove hardcoded user-facing strings; rely on errorCode |
| `lib/providers/auth_provider.dart` | modify | On init, apply `user.preferredLanguage` to localeProvider |
| `lib/main.dart` | modify | Wire `localizationsDelegates`, `supportedLocales`, `locale` from provider |
| `lib/screens/auth/welcome_screen.dart` | modify | Migrate hardcoded strings |
| `lib/screens/auth/login_screen.dart` | modify | Migrate hardcoded strings |
| `lib/screens/settings/settings_screen.dart` | modify | Migrate strings + add Language entry |
| `lib/screens/settings/language_screen.dart` | create | Full-screen language picker |
| `lib/screens/main_shell.dart` | modify | Migrate bottom-nav labels |
| Call sites showing `response.error` | modify | Route through `translateApiError` |
| `test/core/i18n/locale_resolver_test.dart` | create | Unit tests for resolution chain |
| `test/core/i18n/locale_storage_test.dart` | create | Round-trip persistence tests |
| `test/core/i18n/locale_provider_test.dart` | create | Provider behavior tests |
| `test/core/i18n/error_messages_test.dart` | create | errorCode → string mapping |
| `test/models/user_preferred_language_test.dart` | create | fromJson/toJson with field |
| `test/l10n/arb_parity_test.dart` | create | Every key in EN exists in all other ARBs |

---

### Task 1: Dependencies, l10n.yaml, and empty ARB files

**Files:**
- Modify: `pubspec.yaml`
- Create: `l10n.yaml`
- Create: `lib/l10n/app_en.arb`, `app_es.arb`, `app_pt_BR.arb`, `app_fr.arb`, `app_de.arb`, `app_ru.arb`

- [ ] **Step 1: Add `flutter_localizations` and enable codegen in `pubspec.yaml`**

Locate the `dependencies:` block (around line 30) and the `flutter:` block (around line 115). Add these:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:        # ← new
    sdk: flutter                # ← new
  # ... rest unchanged

flutter:
  generate: true                # ← new (first line under flutter:)
  uses-material-design: true
  # ... rest unchanged
```

- [ ] **Step 2: Create `l10n.yaml` at repo root**

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false
synthetic-package: false
output-dir: lib/l10n/gen
```

`synthetic-package: false` + `output-dir` puts the generated file inside the repo so it's easy to inspect (still gitignored via the rule below).

- [ ] **Step 3: Add the generated dir to `.gitignore`**

Append to `.gitignore`:

```
# Generated localizations
lib/l10n/gen/
```

- [ ] **Step 4: Create the seven minimal ARB files**

(See the "Flutter 3.38.7 tooling realities" note in the header for why 7, not 6.)

Each contains just the locale header for now — strings get added in Task 13. The `app_pt.arb` base file is kept identical to `app_pt_BR.arb`.

`lib/l10n/app_en.arb`:
```json
{
  "@@locale": "en",
  "appName": "Flame",
  "@appName": {
    "description": "The app name shown on the welcome screen"
  }
}
```

`lib/l10n/app_es.arb`:
```json
{
  "@@locale": "es",
  "appName": "Flame"
}
```

`lib/l10n/app_pt_BR.arb`:
```json
{
  "@@locale": "pt_BR",
  "appName": "Flame"
}
```

`lib/l10n/app_pt.arb` (base locale — identical to pt_BR; required by gen-l10n):
```json
{
  "@@locale": "pt",
  "appName": "Flame"
}
```

`lib/l10n/app_fr.arb`:
```json
{
  "@@locale": "fr",
  "appName": "Flame"
}
```

`lib/l10n/app_de.arb`:
```json
{
  "@@locale": "de",
  "appName": "Flame"
}
```

`lib/l10n/app_ru.arb`:
```json
{
  "@@locale": "ru",
  "appName": "Flame"
}
```

- [ ] **Step 5: Fetch deps and generate localizations**

Run:
```bash
flutter pub get && flutter gen-l10n
```
Expected: `lib/l10n/gen/app_localizations.dart` exists and exports `AppLocalizations`. No errors.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock l10n.yaml .gitignore lib/l10n/
git commit -m "feat(i18n): scaffold flutter_localizations with empty ARB files"
```

---

### Task 2: Supported locales source of truth

**Files:**
- Create: `lib/core/i18n/supported_locales.dart`
- Test: `test/core/i18n/supported_locales_test.dart`

- [ ] **Step 1: Write the failing test**

`test/core/i18n/supported_locales_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flame/core/i18n/supported_locales.dart';

void main() {
  test('exposes exactly six locales in expected order', () {
    expect(kSupportedLocales, [
      const Locale('en'),
      const Locale('es'),
      const Locale('pt', 'BR'),
      const Locale('fr'),
      const Locale('de'),
      const Locale('ru'),
    ]);
  });

  test('every locale has a non-empty display name', () {
    for (final locale in kSupportedLocales) {
      expect(displayNameOf(locale), isNotEmpty);
    }
  });

  test('display names are in the language itself', () {
    expect(displayNameOf(const Locale('es')), 'Español');
    expect(displayNameOf(const Locale('pt', 'BR')), 'Português (Brasil)');
    expect(displayNameOf(const Locale('de')), 'Deutsch');
    expect(displayNameOf(const Locale('ru')), 'Русский');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/core/i18n/supported_locales_test.dart
```
Expected: FAIL — `supported_locales.dart` doesn't exist.

- [ ] **Step 3: Implement `supported_locales.dart`**

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/core/i18n/supported_locales_test.dart
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/i18n/supported_locales.dart test/core/i18n/supported_locales_test.dart
git commit -m "feat(i18n): add supported locales list + display name helper"
```

---

### Task 3: Locale storage (SharedPreferences round-trip)

**Files:**
- Create: `lib/core/i18n/locale_storage.dart`
- Test: `test/core/i18n/locale_storage_test.dart`

- [ ] **Step 1: Write the failing test**

`test/core/i18n/locale_storage_test.dart`:
```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/core/i18n/locale_storage_test.dart
```
Expected: FAIL — `locale_storage.dart` doesn't exist.

- [ ] **Step 3: Implement `locale_storage.dart`**

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/core/i18n/locale_storage_test.dart
```
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/i18n/locale_storage.dart test/core/i18n/locale_storage_test.dart
git commit -m "feat(i18n): add LocaleStorage SharedPreferences wrapper"
```

---

### Task 4: Locale resolver (pure function)

**Files:**
- Create: `lib/core/i18n/locale_resolver.dart`
- Test: `test/core/i18n/locale_resolver_test.dart`

The resolution chain is the heart of locale logic. Implement it as a pure function so it's trivially testable without mocking SharedPreferences or PlatformDispatcher.

- [ ] **Step 1: Write the failing test**

`test/core/i18n/locale_resolver_test.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/locale_resolver.dart';
import 'package:flame/core/i18n/supported_locales.dart';

void main() {
  test('saved preference wins over device locale', () {
    final result = resolveLocale(
      saved: const Locale('fr'),
      deviceLocales: [const Locale('es')],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('fr'));
  });

  test('device locale wins when no preference saved', () {
    final result = resolveLocale(
      saved: null,
      deviceLocales: [const Locale('es')],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('es'));
  });

  test('walks device locale list and picks first supported match', () {
    final result = resolveLocale(
      saved: null,
      deviceLocales: [
        const Locale('zh'),  // unsupported
        const Locale('ja'),  // unsupported
        const Locale('de'),  // supported — should win
      ],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('de'));
  });

  test('unsupported locale with country falls back to bare language', () {
    final result = resolveLocale(
      saved: null,
      deviceLocales: [const Locale('fr', 'CA')],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('fr'));
  });

  test('pt_BR device locale matches pt_BR supported locale exactly', () {
    final result = resolveLocale(
      saved: null,
      deviceLocales: [const Locale('pt', 'BR')],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('pt', 'BR'));
  });

  test('pt_PT device locale falls back to pt_BR (only Portuguese we have)', () {
    final result = resolveLocale(
      saved: null,
      deviceLocales: [const Locale('pt', 'PT')],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('pt', 'BR'));
  });

  test('unsupported language falls back to English', () {
    final result = resolveLocale(
      saved: null,
      deviceLocales: [const Locale('zh')],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('en'));
  });

  test('empty device locales falls back to English', () {
    final result = resolveLocale(
      saved: null,
      deviceLocales: const [],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('en'));
  });

  test('saved preference that is unsupported is ignored', () {
    // Defensive: if a user somehow has a stale unsupported tag stored,
    // we shouldn't honor it.
    final result = resolveLocale(
      saved: const Locale('zh'),
      deviceLocales: [const Locale('es')],
      supported: kSupportedLocales,
    );
    expect(result, const Locale('es'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/core/i18n/locale_resolver_test.dart
```
Expected: FAIL — `locale_resolver.dart` doesn't exist.

- [ ] **Step 3: Implement `locale_resolver.dart`**

```dart
import 'package:flutter/widgets.dart';

/// Pure resolution of which [Locale] the app should display.
///
/// Resolution chain (top wins):
///   1. [saved] preference (from SharedPreferences) — if supported
///   2. First entry in [deviceLocales] that matches a supported locale exactly
///   3. First entry in [deviceLocales] whose language code (ignoring country)
///      matches a supported locale's language code
///   4. English ('en') as the hard fallback
Locale resolveLocale({
  required Locale? saved,
  required List<Locale> deviceLocales,
  required List<Locale> supported,
}) {
  // 1. Saved preference — exact or language-code match
  if (saved != null) {
    final match = _findMatch(saved, supported);
    if (match != null) return match;
  }

  // 2. Device locales — exact match preferred
  for (final device in deviceLocales) {
    for (final s in supported) {
      if (s == device) return s;
    }
  }

  // 3. Device locales — language code match
  for (final device in deviceLocales) {
    for (final s in supported) {
      if (s.languageCode == device.languageCode) return s;
    }
  }

  // 4. Hard fallback
  return const Locale('en');
}

Locale? _findMatch(Locale candidate, List<Locale> supported) {
  for (final s in supported) {
    if (s == candidate) return s;
  }
  for (final s in supported) {
    if (s.languageCode == candidate.languageCode) return s;
  }
  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/core/i18n/locale_resolver_test.dart
```
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/i18n/locale_resolver.dart test/core/i18n/locale_resolver_test.dart
git commit -m "feat(i18n): add pure locale resolution function"
```

---

### Task 5: Locale provider (Riverpod)

**Files:**
- Create: `lib/core/i18n/locale_provider.dart`
- Test: `test/core/i18n/locale_provider_test.dart`

- [ ] **Step 1: Write the failing test**

`test/core/i18n/locale_provider_test.dart`:
```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/core/i18n/locale_provider_test.dart
```
Expected: FAIL — `locale_provider.dart` doesn't exist.

- [ ] **Step 3: Implement `locale_provider.dart`**

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/core/i18n/locale_provider_test.dart
```
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/i18n/locale_provider.dart test/core/i18n/locale_provider_test.dart
git commit -m "feat(i18n): add Riverpod locale provider"
```

---

### Task 6: BuildContext extension for ergonomic access

**Files:**
- Create: `lib/core/i18n/build_context_ext.dart`

- [ ] **Step 1: Implement the extension**

```dart
import 'package:flutter/widgets.dart';
import '../../l10n/gen/app_localizations.dart';

extension L10nX on BuildContext {
  /// Short alias for `AppLocalizations.of(this)` so widgets can read
  /// `context.l10n.welcomeTitle` instead of the verbose form.
  AppLocalizations get l10n => AppLocalizations.of(this);
}
```

(Note: `nullable-getter: false` in `l10n.yaml` makes `AppLocalizations.of` return non-null — no `!` needed.)

- [ ] **Step 2: Verify it compiles**

```bash
flutter analyze lib/core/i18n/build_context_ext.dart
```
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/core/i18n/build_context_ext.dart
git commit -m "feat(i18n): add context.l10n extension alias"
```

---

### Task 7: User model — preferredLanguage field

**Files:**
- Modify: `lib/models/user.dart`
- Test: `test/models/user_preferred_language_test.dart`

- [ ] **Step 1: Write the failing test**

`test/models/user_preferred_language_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';

Map<String, dynamic> _baseJson() => {
      'id': '1',
      'name': 'Alice',
      'age': 30,
      'bio': '',
      'photos': <String>[],
      'location': '',
      'interests': <String>[],
      'gender': 'female',
      'looking_for': 'male',
    };

void main() {
  test('fromJson reads preferred_language when present', () {
    final json = _baseJson()..['preferred_language'] = 'es';
    final user = User.fromJson(json);
    expect(user.preferredLanguage, 'es');
  });

  test('fromJson reads pt-BR style country-coded tag', () {
    final json = _baseJson()..['preferred_language'] = 'pt-BR';
    final user = User.fromJson(json);
    expect(user.preferredLanguage, 'pt-BR');
  });

  test('fromJson sets preferredLanguage to null when field absent', () {
    final user = User.fromJson(_baseJson());
    expect(user.preferredLanguage, isNull);
  });

  test('toJson includes preferred_language', () {
    final user = User.fromJson(_baseJson()..['preferred_language'] = 'fr');
    expect(user.toJson()['preferred_language'], 'fr');
  });

  test('copyWith updates preferredLanguage', () {
    final user = User.fromJson(_baseJson());
    final updated = user.copyWith(preferredLanguage: 'de');
    expect(updated.preferredLanguage, 'de');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/models/user_preferred_language_test.dart
```
Expected: FAIL — `preferredLanguage` getter doesn't exist on User.

- [ ] **Step 3: Add the field to `lib/models/user.dart`**

Add the field declaration after `isProfileComplete`:

```dart
  final bool? isProfileComplete;
  // BCP 47 short form (e.g. "en", "es", "pt-BR"). Null when the user hasn't
  // explicitly picked a language in app settings.
  final String? preferredLanguage;
```

Add to the constructor:
```dart
    this.isProfileComplete,
    this.preferredLanguage,
  });
```

Add to `fromJson` (after `isProfileComplete: json['is_profile_complete']...`):
```dart
      isProfileComplete: json['is_profile_complete'] as bool?,
      preferredLanguage: json['preferred_language'] as String?,
```

Add to `toJson`:
```dart
      'super_likes_remaining': superLikesRemaining,
      'preferred_language': preferredLanguage,
    };
```

Add to `copyWith` parameter list:
```dart
    bool? isProfileComplete,
    String? preferredLanguage,
  }) {
```

And to the body:
```dart
      isProfileComplete: isProfileComplete ?? this.isProfileComplete,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
    );
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/models/user_preferred_language_test.dart
```
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/models/user.dart test/models/user_preferred_language_test.dart
git commit -m "feat(user): add preferredLanguage field (BCP 47 short form)"
```

---

### Task 8: AuthService — updatePreferredLanguage

**Files:**
- Modify: `lib/services/auth_service.dart`

This is a thin wrapper around `PATCH /v1/users/me`. We don't need a new unit test because it's a one-line API call — the existing `User.fromJson` test (Task 7) covers parsing the response. Manual verification via the app exercises the call.

- [ ] **Step 1: Locate where AuthService talks to `/users/me`**

```bash
grep -n "users/me\|updateProfile" lib/services/auth_service.dart
```

You'll find an existing `updateProfile` or similar method. The pattern is `_apiClient.patch('/users/me', body: {...})`.

- [ ] **Step 2: Add the method**

Add this method anywhere in `AuthService`:

```dart
  /// Persists the user's preferred language to the backend.
  ///
  /// Best-effort — failures are returned but the app continues using the
  /// local preference. Backend may not have the field yet during deploy.
  Future<ApiResponse> updatePreferredLanguage(String code) async {
    return _apiClient.patch('/users/me', body: {
      'preferred_language': code,
    });
  }
```

- [ ] **Step 3: Verify it compiles**

```bash
flutter analyze lib/services/auth_service.dart
```
Expected: No new issues.

- [ ] **Step 4: Commit**

```bash
git add lib/services/auth_service.dart
git commit -m "feat(auth): add updatePreferredLanguage backend sync method"
```

---

### Task 9: AuthNotifier — apply user.preferredLanguage on init

**Files:**
- Modify: `lib/providers/auth_provider.dart`

- [ ] **Step 1: Add the locale-sync call to `_init`**

Find this block (currently near line 60):

```dart
      if (result.success && result.user != null) {
        final user = await _withPremiumFromBilling(result.user!);
        state = state.copyWith(
          status: _statusFor(user),
          user: user,
          isLoading: false,
        );
      }
```

The locale-sync should run only after the user is loaded. Since `AuthNotifier` doesn't have a `Ref`, we need to expose this through a separate provider that depends on both `authProvider` and `localeProvider`. Cleanest place: add a `ref.listen` in `main.dart` (Task 12). Skip touching auth_provider here — the sync gets wired in Task 12 where Ref is available.

This step is intentionally a no-op. The plan keeps it explicit so you don't go looking for code that isn't there.

- [ ] **Step 2: Commit (empty — skip if no changes)**

If you made no changes, no commit. Continue.

---

### Task 10: Error message translation map

**Files:**
- Modify: `lib/l10n/app_en.arb` and the other 5 ARBs (add error keys)
- Create: `lib/core/i18n/error_messages.dart`
- Test: `test/core/i18n/error_messages_test.dart`

- [ ] **Step 1: Add error keys to `lib/l10n/app_en.arb`**

Insert (alongside `appName`):

```json
{
  "@@locale": "en",
  "appName": "Flame",
  "@appName": {"description": "The app name shown on the welcome screen"},

  "errorInvalidCredentials": "Incorrect email or password.",
  "@errorInvalidCredentials": {"description": "Shown when login fails due to bad credentials"},

  "errorEmailExists": "An account with this email already exists.",
  "@errorEmailExists": {"description": "Shown during registration when email is taken"},

  "errorRateLimited": "You're doing that too often. Please try again in a moment.",
  "@errorRateLimited": {"description": "Shown when the backend returns 429"},

  "errorAuthLost": "Your session has ended. Please sign in again.",
  "@errorAuthLost": {"description": "Shown when the access token can't be refreshed"},

  "errorNoInternet": "No internet connection.",
  "@errorNoInternet": {"description": "Shown when the device is offline"},

  "errorGeneric": "Something went wrong. Please try again.",
  "@errorGeneric": {"description": "Fallback for unknown errors"}
}
```

- [ ] **Step 2: Mirror the keys (English values, no metadata) into the other 6 ARBs**

Each of `app_es.arb`, `app_pt.arb`, `app_pt_BR.arb`, `app_fr.arb`, `app_de.arb`, `app_ru.arb` gets the same keys with English values for now. Real translations land later. `app_pt.arb` and `app_pt_BR.arb` must stay in sync — every key in both, with identical values. Example for `app_es.arb`:

```json
{
  "@@locale": "es",
  "appName": "Flame",
  "errorInvalidCredentials": "Incorrect email or password.",
  "errorEmailExists": "An account with this email already exists.",
  "errorRateLimited": "You're doing that too often. Please try again in a moment.",
  "errorAuthLost": "Your session has ended. Please sign in again.",
  "errorNoInternet": "No internet connection.",
  "errorGeneric": "Something went wrong. Please try again."
}
```

Apply the same to all 5.

- [ ] **Step 3: Regenerate localizations**

```bash
flutter gen-l10n
```
Expected: `lib/l10n/gen/app_localizations.dart` now has getters like `errorInvalidCredentials`.

- [ ] **Step 4: Write the failing test for `translateApiError`**

`test/core/i18n/error_messages_test.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/error_messages.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/services/api_client.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('maps INVALID_CREDENTIALS to localized string', () {
    final r = ApiResponse(success: false, errorCode: 'INVALID_CREDENTIALS', statusCode: 401);
    expect(translateApiError(l10n, r), 'Incorrect email or password.');
  });

  test('maps RATE_LIMITED to localized string', () {
    final r = ApiResponse(success: false, errorCode: 'RATE_LIMITED', statusCode: 429);
    expect(translateApiError(l10n, r), contains('too often'));
  });

  test('maps AUTH_LOST to localized string', () {
    final r = ApiResponse(success: false, errorCode: 'AUTH_LOST', statusCode: 401);
    expect(translateApiError(l10n, r), contains('session has ended'));
  });

  test('unknown errorCode falls back to backend error string', () {
    final r = ApiResponse(
      success: false,
      errorCode: 'SOMETHING_NEW',
      error: 'Backend said this',
      statusCode: 400,
    );
    expect(translateApiError(l10n, r), 'Backend said this');
  });

  test('unknown errorCode with no error string falls back to generic', () {
    final r = ApiResponse(success: false, errorCode: 'WHATEVER', statusCode: 500);
    expect(translateApiError(l10n, r), 'Something went wrong. Please try again.');
  });

  test('null errorCode with backend message uses backend message', () {
    final r = ApiResponse(success: false, error: 'Network blip', statusCode: 0);
    expect(translateApiError(l10n, r), 'Network blip');
  });
}
```

- [ ] **Step 5: Run test to verify it fails**

```bash
flutter test test/core/i18n/error_messages_test.dart
```
Expected: FAIL — `error_messages.dart` doesn't exist.

- [ ] **Step 6: Implement `error_messages.dart`**

```dart
import '../../l10n/gen/app_localizations.dart';
import '../../services/api_client.dart';

/// Maps an [ApiResponse] error to a localized user-facing string.
///
/// The backend returns stable `errorCode` values; this is the single place
/// the client decides which translation key to show. Unknown codes fall back
/// to the backend's English [ApiResponse.error] message, or — if even that
/// is missing — to a generic fallback.
String translateApiError(AppLocalizations l10n, ApiResponse response) {
  switch (response.errorCode) {
    case 'INVALID_CREDENTIALS':
      return l10n.errorInvalidCredentials;
    case 'EMAIL_EXISTS':
      return l10n.errorEmailExists;
    case 'RATE_LIMITED':
      return l10n.errorRateLimited;
    case 'AUTH_LOST':
      return l10n.errorAuthLost;
  }
  return response.error ?? l10n.errorGeneric;
}
```

- [ ] **Step 7: Run test to verify it passes**

```bash
flutter test test/core/i18n/error_messages_test.dart
```
Expected: PASS (6 tests).

- [ ] **Step 8: Commit**

```bash
git add lib/l10n/*.arb lib/core/i18n/error_messages.dart test/core/i18n/error_messages_test.dart
git commit -m "feat(i18n): add translateApiError mapping with 6 error keys"
```

---

### Task 11: Make ApiClient locale-agnostic

**Files:**
- Modify: `lib/services/api_client.dart`

Today `ApiClient` builds two user-facing English strings: the 429 "Slow down" message and the `_onAuthLost` "Your session has ended" message. Move those into the ARB-driven flow by leaving only `errorCode` on the response.

- [ ] **Step 1: Strip the 429 message in `_handleResponse`**

Find the `} else if (statusCode == 429) {` block. Replace the `error:` value:

```dart
    } else if (statusCode == 429) {
      // Rate limited. Surface only errorCode — UI translates via
      // translateApiError(). Retry-after preserved in error string for any
      // log/diagnostic display.
      final retryAfter = response.headers['retry-after'];
      final retryHint = retryAfter != null ? ' (retry-after: ${retryAfter}s)' : '';
      return ApiResponse(
        success: false,
        data: data,
        error: 'Rate limited$retryHint',
        errorCode: 'RATE_LIMITED',
        statusCode: statusCode,
      );
    }
```

- [ ] **Step 2: Strip the user-facing string in `_onAuthLost`**

Find the `_onAuthLost` method. Replace the returned `error`:

```dart
  Future<ApiResponse> _onAuthLost() async {
    await clearTokens();
    try {
      await onAuthLost?.call();
    } catch (_) {}
    return ApiResponse(
      success: false,
      error: 'Auth lost',
      errorCode: 'AUTH_LOST',
      statusCode: 401,
    );
  }
```

- [ ] **Step 3: Verify the tests still pass**

```bash
flutter test
```
Expected: PASS. Anything that asserts on the old English strings needs to be updated — most likely there are no such tests, but if there are, switch them to assert on `errorCode`.

- [ ] **Step 4: Commit**

```bash
git add lib/services/api_client.dart
git commit -m "refactor(api): drop user-facing strings from ApiClient (l10n moves to UI)"
```

---

### Task 12: Wire MaterialApp + initialize locale at startup

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Read current `main.dart`**

```bash
cat lib/main.dart | head -60
```

You'll see a `MaterialApp` inside a `ConsumerWidget` or a stateful build, with `home:` pointing at the auth/shell decision. We'll add three things: `localizationsDelegates`, `supportedLocales`, and a reactive `locale`.

- [ ] **Step 2: Update imports and main()**

At the top of `main.dart`, add:
```dart
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/i18n/locale_provider.dart';
import 'core/i18n/supported_locales.dart';
import 'l10n/gen/app_localizations.dart';
```

In `main()`, before `runApp(...)`, initialize the locale:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ...existing setup...
  final container = ProviderContainer();
  await container.read(localeProvider.notifier).initialize(
    deviceLocales: WidgetsBinding.instance.platformDispatcher.locales,
  );
  runApp(UncontrolledProviderScope(container: container, child: const FlameApp()));
}
```

If `main()` currently uses `ProviderScope`, replace with `UncontrolledProviderScope(container: ...)` so the same container that resolved the locale is the one widgets read.

- [ ] **Step 3: Update MaterialApp builder to consume `localeProvider`**

Inside the widget that builds `MaterialApp` (a `Consumer` or `ConsumerWidget`), read the locale and pass everything:

```dart
final locale = ref.watch(localeProvider);

return MaterialApp(
  // ...existing properties...
  locale: locale,
  supportedLocales: kSupportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
);
```

- [ ] **Step 4: Sync backend-stored language at startup**

Still in the `MaterialApp` builder widget (which has `ref`), add a one-time listener that watches the authenticated user and applies their backend `preferredLanguage` if it differs from the local one:

```dart
ref.listen<AuthState>(authProvider, (previous, next) {
  final user = next.user;
  if (user == null || user.preferredLanguage == null) return;
  final desired = _parseLocaleTag(user.preferredLanguage!);
  if (desired == null) return;
  final current = ref.read(localeProvider);
  if (current == desired) return;
  // Backend wins on launch (user may have changed language on another device).
  ref.read(localeProvider.notifier).setLocale(desired);
});
```

And add `_parseLocaleTag` as a private helper in the file:

```dart
Locale? _parseLocaleTag(String tag) {
  final parts = tag.split('-');
  if (parts.isEmpty) return null;
  if (parts.length == 1) return Locale(parts[0]);
  if (parts.length == 2) return Locale(parts[0], parts[1]);
  return null;
}
```

- [ ] **Step 5: Run the app to verify**

```bash
flutter run
```
Expected: App launches normally. Nothing visibly changes yet (no strings migrated), but `MaterialApp.locale` is now driven by the provider and the app supports the 6 locales.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart
git commit -m "feat(i18n): wire MaterialApp delegates and reactive locale"
```

---

### Task 13: Populate ARB files with all Phase 0 keys

**Files:**
- Modify: `lib/l10n/app_en.arb` and the other 5 ARBs

Add every string the Phase 0 screens will use. After this task, the screens still show hardcoded text — Tasks 14-18 migrate them.

- [ ] **Step 1: Replace `lib/l10n/app_en.arb` with the full Phase 0 set**

```json
{
  "@@locale": "en",

  "appName": "Flame",
  "@appName": {"description": "The app name"},
  "appTagline": "Where conversations spark",
  "@appTagline": {"description": "Subtitle on the welcome screen"},

  "welcomeSignIn": "Sign in",
  "@welcomeSignIn": {"description": "Button to go to login screen"},
  "welcomeCreateAccount": "Create account",
  "@welcomeCreateAccount": {"description": "Button to start registration"},

  "loginTitle": "Welcome back",
  "loginEmailLabel": "Email",
  "loginPasswordLabel": "Password",
  "loginForgotPassword": "Forgot password?",
  "loginSubmit": "Sign in",
  "loginGoogle": "Continue with Google",
  "loginApple": "Continue with Apple",
  "loginFacebook": "Continue with Facebook",
  "loginNoAccount": "Don't have an account?",
  "loginSignUpLink": "Sign up",

  "navHome": "Home",
  "navMatches": "Matches",
  "navChat": "Chat",
  "navProfile": "Profile",
  "navSettings": "Settings",

  "settingsTitle": "Settings",
  "settingsAccount": "Account",
  "settingsNotifications": "Notifications",
  "settingsLanguage": "Language",
  "@settingsLanguage": {"description": "Row label for the language picker"},
  "settingsPrivacy": "Privacy",
  "settingsLogout": "Log out",
  "settingsLogoutConfirmTitle": "Log out",
  "settingsLogoutConfirmBody": "Are you sure you want to log out?",
  "settingsCancel": "Cancel",
  "settingsDelete": "Delete",
  "settingsDeleteAccount": "Delete account",
  "settingsDeleteAccountBody": "This permanently deletes your account and all your data.",

  "languagePickerTitle": "Language",
  "languageUseDevice": "Use device language",
  "@languageUseDevice": {"description": "Row that clears the override and uses the system language"},

  "errorInvalidCredentials": "Incorrect email or password.",
  "errorEmailExists": "An account with this email already exists.",
  "errorRateLimited": "You're doing that too often. Please try again in a moment.",
  "errorAuthLost": "Your session has ended. Please sign in again.",
  "errorNoInternet": "No internet connection.",
  "errorGeneric": "Something went wrong. Please try again."
}
```

- [ ] **Step 2: Copy these key/value pairs (no `@`-metadata) into the other 5 ARB files**

For each of `app_es.arb`, `app_pt_BR.arb`, `app_fr.arb`, `app_de.arb`, `app_ru.arb`, set the file to have `@@locale` plus every non-`@` key with the same English value (placeholder until real translation lands). Example for `app_de.arb`:

```json
{
  "@@locale": "de",
  "appName": "Flame",
  "appTagline": "Where conversations spark",
  "welcomeSignIn": "Sign in",
  "welcomeCreateAccount": "Create account",
  "loginTitle": "Welcome back",
  "loginEmailLabel": "Email",
  "loginPasswordLabel": "Password",
  "loginForgotPassword": "Forgot password?",
  "loginSubmit": "Sign in",
  "loginGoogle": "Continue with Google",
  "loginApple": "Continue with Apple",
  "loginFacebook": "Continue with Facebook",
  "loginNoAccount": "Don't have an account?",
  "loginSignUpLink": "Sign up",
  "navHome": "Home",
  "navMatches": "Matches",
  "navChat": "Chat",
  "navProfile": "Profile",
  "navSettings": "Settings",
  "settingsTitle": "Settings",
  "settingsAccount": "Account",
  "settingsNotifications": "Notifications",
  "settingsLanguage": "Language",
  "settingsPrivacy": "Privacy",
  "settingsLogout": "Log out",
  "settingsLogoutConfirmTitle": "Log out",
  "settingsLogoutConfirmBody": "Are you sure you want to log out?",
  "settingsCancel": "Cancel",
  "settingsDelete": "Delete",
  "settingsDeleteAccount": "Delete account",
  "settingsDeleteAccountBody": "This permanently deletes your account and all your data.",
  "languagePickerTitle": "Language",
  "languageUseDevice": "Use device language",
  "errorInvalidCredentials": "Incorrect email or password.",
  "errorEmailExists": "An account with this email already exists.",
  "errorRateLimited": "You're doing that too often. Please try again in a moment.",
  "errorAuthLost": "Your session has ended. Please sign in again.",
  "errorNoInternet": "No internet connection.",
  "errorGeneric": "Something went wrong. Please try again."
}
```

Repeat for ES, PT-BR, FR, RU.

- [ ] **Step 3: Regenerate localizations**

```bash
flutter gen-l10n
```
Expected: succeeds with no warnings about missing keys.

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/*.arb
git commit -m "feat(i18n): populate Phase 0 strings (English values across all 6 ARBs)"
```

---

### Task 14: Migrate `welcome_screen.dart`

**Files:**
- Modify: `lib/screens/auth/welcome_screen.dart`

- [ ] **Step 1: Replace every hardcoded user-facing string with `context.l10n.*`**

Add the import:
```dart
import 'package:flame/core/i18n/build_context_ext.dart';
```

Replace strings like:
```dart
Text('Welcome to Flame')      → Text(context.l10n.appName)
Text('Sign in')               → Text(context.l10n.welcomeSignIn)
Text('Create account')        → Text(context.l10n.welcomeCreateAccount)
```

Walk the file top to bottom. Every `Text('...')`, `Tooltip(message: '...')`, `SnackBar(content: Text('...'))` etc. needs migration. Don't change `const Text` — drop the `const` when adding `context.l10n.*` since the value is now runtime.

- [ ] **Step 2: Verify it compiles and renders**

```bash
flutter run
```
Tap to navigate to welcome screen, confirm strings match.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/auth/welcome_screen.dart
git commit -m "feat(i18n): migrate welcome screen to AppLocalizations"
```

---

### Task 15: Migrate `login_screen.dart`

**Files:**
- Modify: `lib/screens/auth/login_screen.dart`

Same pattern as Task 14. Strings include the form labels (Email, Password), buttons (Sign in, Forgot password?), social-button labels (Continue with Google/Apple/Facebook), and the "Don't have an account? Sign up" footer.

- [ ] **Step 1: Add the import**

```dart
import 'package:flame/core/i18n/build_context_ext.dart';
```

- [ ] **Step 2: Replace strings**

Map each existing string to its key from `app_en.arb` (Task 13). Example:
```dart
TextField(decoration: InputDecoration(labelText: 'Email'))
  → TextField(decoration: InputDecoration(labelText: context.l10n.loginEmailLabel))
```

- [ ] **Step 3: Route the login error snackbar through `translateApiError`**

Find where the login error displays in the snackbar (look for `ScaffoldMessenger.of(context).showSnackBar` near the login handler). The current code shows the raw `error` string from auth state. Change to:

```dart
import 'package:flame/core/i18n/error_messages.dart';
import 'package:flame/services/api_client.dart';

// In the snackbar callback:
final message = translateApiError(
  context.l10n,
  ApiResponse(
    success: false,
    error: state.error,
    errorCode: state.errorCode, // null today; we'll add this in a follow-up
    statusCode: 0,
  ),
);
```

(Note: `AuthState.error` is currently a plain String. The full migration of `errorCode` propagation to AuthState belongs in Phase 1 — for now this gracefully degrades when `errorCode` is null and shows the raw error string. Acceptable for Phase 0.)

- [ ] **Step 4: Verify**

```bash
flutter run
```
Try logging in. Confirm labels and buttons render correctly.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/auth/login_screen.dart
git commit -m "feat(i18n): migrate login screen to AppLocalizations"
```

---

### Task 16: Migrate `settings_screen.dart` + add Language entry

**Files:**
- Modify: `lib/screens/settings/settings_screen.dart`

- [ ] **Step 1: Add imports**

```dart
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/screens/settings/language_screen.dart';
import 'package:flame/core/i18n/locale_provider.dart';
import 'package:flame/core/i18n/supported_locales.dart';
```

- [ ] **Step 2: Migrate all hardcoded strings**

Replace `Text('Settings')` → `Text(context.l10n.settingsTitle)`, dialogue titles, "Log Out" → `context.l10n.settingsLogout`, etc. Use the keys defined in Task 13.

- [ ] **Step 3: Add the Language list tile**

Insert near the other settings rows (e.g., between Notifications and Privacy):

```dart
ListTile(
  leading: const Icon(Icons.language_outlined),
  title: Text(context.l10n.settingsLanguage),
  trailing: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(displayNameOf(ref.watch(localeProvider) ?? const Locale('en'))),
      const SizedBox(width: 8),
      const Icon(Icons.chevron_right),
    ],
  ),
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LanguageScreen()),
    );
  },
),
```

If `settings_screen.dart` is not a `ConsumerWidget`/`ConsumerStatefulWidget`, change it to one so `ref.watch` works.

- [ ] **Step 4: Verify**

```bash
flutter run
```
Open Settings, confirm the Language row shows the current language name on the right.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/settings/settings_screen.dart
git commit -m "feat(i18n): migrate settings screen + add Language entry"
```

---

### Task 17: Create LanguageScreen picker

**Files:**
- Create: `lib/screens/settings/language_screen.dart`

- [ ] **Step 1: Implement the full screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/i18n/locale_provider.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/services/auth_service.dart';

class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.languagePickerTitle)),
      body: ListView(
        children: [
          for (final locale in kSupportedLocales)
            RadioListTile<Locale>(
              value: locale,
              groupValue: current,
              onChanged: (picked) => _select(context, ref, picked),
              title: Text(displayNameOf(locale)),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.phone_iphone),
            title: Text(context.l10n.languageUseDevice),
            onTap: () => _useDevice(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _select(BuildContext context, WidgetRef ref, Locale? picked) async {
    if (picked == null) return;
    await ref.read(localeProvider.notifier).setLocale(picked);
    // Fire-and-forget backend sync. Failure is non-fatal — the local
    // preference still wins until next backend-on-launch reconciliation.
    AuthService().updatePreferredLanguage(picked.toLanguageTag());
  }

  Future<void> _useDevice(BuildContext context, WidgetRef ref) async {
    await ref.read(localeProvider.notifier).clearLocale(
      deviceLocales: WidgetsBinding.instance.platformDispatcher.locales,
    );
    // Send the resolved locale (post-clear) to the backend so it stays in sync.
    final resolved = ref.read(localeProvider);
    if (resolved != null) {
      AuthService().updatePreferredLanguage(resolved.toLanguageTag());
    }
  }
}
```

- [ ] **Step 2: Verify the screen builds and switches locale**

```bash
flutter run
```

In the running app: Settings → Language → pick "Español" → screen labels switch to whatever Spanish strings exist (currently English placeholders, but the **Language picker title** itself will re-render). Pick "Use device language" — current selection reverts.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/settings/language_screen.dart
git commit -m "feat(i18n): add language picker screen"
```

---

### Task 18: Migrate `main_shell.dart` bottom-nav labels

**Files:**
- Modify: `lib/screens/main_shell.dart`

- [ ] **Step 1: Find the navigation items**

```bash
grep -n "BottomNavigationBarItem\|NavigationDestination\|label:" lib/screens/main_shell.dart | head
```

Each item has a `label: 'Home'` (or similar). Replace with `context.l10n.navHome`, `context.l10n.navMatches`, etc.

- [ ] **Step 2: Add the import + migrate**

```dart
import 'package:flame/core/i18n/build_context_ext.dart';
```

```dart
BottomNavigationBarItem(icon: Icon(Icons.home), label: context.l10n.navHome),
BottomNavigationBarItem(icon: Icon(Icons.favorite), label: context.l10n.navMatches),
// etc.
```

Drop `const` from each item since `context.l10n.*` is runtime.

- [ ] **Step 3: Verify**

```bash
flutter run
```
Switch language in Settings → bottom-nav labels update live.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/main_shell.dart
git commit -m "feat(i18n): migrate main shell bottom-nav labels"
```

---

### Task 19: Route auth-related snackbars through translateApiError

**Files:**
- Modify: `lib/providers/chat_provider.dart`, `lib/providers/swipe_provider.dart`, and any other place that surfaces `response.error` as a snackbar

The 429 path and AUTH_LOST path no longer carry English strings (Task 11). Call sites that just show `response.error` will now show "Rate limited" or "Auth lost" — ugly. Route them through `translateApiError` so they show the localized message.

- [ ] **Step 1: Locate snackbar sites that display response.error**

```bash
grep -rn "_showError\|_showSwipeError\|showSnackBar.*error" lib/screens/ lib/providers/
```

You'll see ~12 sites. The pattern across providers (chat_provider.dart, swipe_provider.dart) is: `return result.error ?? 'Failed to ...'`.

- [ ] **Step 2: Switch each return to errorCode-aware translation**

Change provider returns from raw error strings to a tuple of `(errorCode, error)`. Simplest delta: extend the signatures to return `ApiResponse?` instead of `String?` — but that's a bigger refactor than Phase 0 deserves.

Pragmatic shortcut for Phase 0: keep the `Future<String?>` signature, but inside the provider, when `result.errorCode == 'RATE_LIMITED'` or `result.errorCode == 'AUTH_LOST'`, look up the translation locally via a synchronous mapping helper that doesn't need `BuildContext` (the providers don't have one):

Create `lib/core/i18n/error_strings_for.dart`:

```dart
import 'package:flutter/widgets.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../services/api_client.dart';
import 'error_messages.dart';

/// Provider-friendly wrapper: looks up the AppLocalizations for [locale]
/// synchronously from the in-memory cache populated at app startup, then
/// runs the same mapping translateApiError() uses.
class ErrorStringsFor {
  static AppLocalizations? _cached;
  static void prime(AppLocalizations l) { _cached = l; }
  static String message(ApiResponse r) {
    final l10n = _cached;
    if (l10n == null) return r.error ?? 'Error';
    return translateApiError(l10n, r);
  }
}
```

In `main.dart`, after MaterialApp builds and AppLocalizations is loaded, prime the cache. The cleanest hook: a `Builder` inside MaterialApp that calls `ErrorStringsFor.prime(AppLocalizations.of(context))` on each build. (The cache always reflects current locale.)

In chat/swipe providers, change failure returns:
```dart
return result.error ?? 'Failed to send message';
   ↓
return ErrorStringsFor.message(result);
```

- [ ] **Step 3: Verify**

```bash
flutter test && flutter run
```
Trigger a 429 (rapid swipes) — snackbar shows the localized "You're doing that too often" message.

- [ ] **Step 4: Commit**

```bash
git add lib/core/i18n/error_strings_for.dart lib/main.dart lib/providers/chat_provider.dart lib/providers/swipe_provider.dart
git commit -m "feat(i18n): route provider error snackbars through translation"
```

---

### Task 20: ARB parity test

**Files:**
- Create: `test/l10n/arb_parity_test.dart`

- [ ] **Step 1: Write the test**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _readArb(String name) {
  final file = File('lib/l10n/$name');
  expect(file.existsSync(), isTrue, reason: '$name not found at ${file.path}');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Set<String> _stringKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  test('every key in app_en.arb has a translation in all other ARBs', () {
    final en = _stringKeys(_readArb('app_en.arb'));
    expect(en, isNotEmpty, reason: 'app_en.arb should define some keys');

    const others = ['app_es.arb', 'app_pt.arb', 'app_pt_BR.arb', 'app_fr.arb', 'app_de.arb', 'app_ru.arb'];

    for (final name in others) {
      final keys = _stringKeys(_readArb(name));
      expect(
        keys,
        equals(en),
        reason: '$name key set must exactly match app_en.arb',
      );
    }
  });
}
```

- [ ] **Step 2: Run the test**

```bash
flutter test test/l10n/arb_parity_test.dart
```
Expected: PASS (Tasks 10 + 13 ensured parity).

- [ ] **Step 3: Commit**

```bash
git add test/l10n/arb_parity_test.dart
git commit -m "test(i18n): assert ARB key parity across all locales"
```

---

### Task 21: Manual visual QA across all 6 locales

**Files:**
- None (verification only)

- [ ] **Step 1: Run the app**

```bash
flutter run
```

- [ ] **Step 2: For each of the 6 locales, verify these screens render without layout breakage**

In the running app: Settings → Language → pick each in turn. For each language, walk through:
- Welcome screen — buttons fit, no overflow
- Login screen — form labels, social buttons, submit button
- Settings screen — every row, dialog content
- Language picker — title and rows
- Bottom nav — all 5 labels visible

**German and Russian are the usual offenders** for cramped buttons. If you see overflow yellow-and-black warnings, file a follow-up issue with a screenshot and key name — that's a text-fitting issue, not a localization bug.

- [ ] **Step 3: Verify backend sync (if backend has `preferred_language` deployed)**

- In Settings → Language pick a non-English language
- Force-quit the app
- Re-launch
- Confirm the app loads in the picked language (proves SharedPreferences persistence)
- Optional: hit the backend's `/v1/users/me` endpoint directly (curl or API tool) to confirm `preferred_language` was PATCHed

- [ ] **Step 4: Mark Phase 0 done**

```bash
git tag i18n-phase0
git push origin HEAD --tags
```

---

## Summary

After all tasks complete:
- App supports 6 locales (English values across the board until real translations land)
- Device locale auto-detected at launch; user override persisted locally + synced to backend
- Bottom-nav, welcome, login, settings, language picker fully translated via `context.l10n`
- API error codes routed through `translateApiError` for consistent localized error display
- Three layers of test coverage: locale resolution, error mapping, ARB parity
- Codegen guarantees no missing keys at build time

Phases 1-4 (onboarding, registration, discovery, chat) follow as separate specs.
