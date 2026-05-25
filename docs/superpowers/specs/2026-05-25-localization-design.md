# Localization (i18n) — Phase 0 Infrastructure

**Status:** Approved, ready for implementation plan
**Date:** 2026-05-25
**Scope:** Set up the localization system end-to-end and translate the app shell. Subsequent screen migration is out of scope for this spec (Phase 1+ have their own specs).

---

## Problem

The app ships with hardcoded English strings throughout. The target audience is international, but every user — regardless of device language — sees English. We need a localization system that:

1. Supports six languages at launch (English, Spanish, Portuguese-Brazil, French, German, Russian)
2. Auto-detects the user's preferred language from the OS
3. Lets the user override the auto-detection in app settings
4. Persists the override locally and syncs it to the backend so it follows the user across devices
5. Localizes backend error messages without requiring backend i18n
6. Sets the foundation for translating every screen incrementally, without a single massive migration PR

---

## Decisions (settled during brainstorming)

| Decision | Choice |
|---|---|
| Languages | EN, ES, PT-BR, FR, DE, RU — all LTR, no RTL pass needed |
| Detection | Device locale auto-detect; manual override in Settings |
| Persistence | SharedPreferences locally, synced to backend via `preferred_language` field on User (BCP 47 short form: `en`, `es`, `pt-BR`, `fr`, `de`, `ru`) |
| Backend errors | Client-side `errorCode → translated string` map; fall back to backend's English on unknown codes |
| Framework | `flutter_localizations` SDK + ARB files + `gen_l10n` codegen (official, type-safe, standard format) |

---

## Architecture & file layout

```
pubspec.yaml
  ├── dependencies:
  │     flutter_localizations:        ← new (Flutter SDK)
  │       sdk: flutter
  │     intl: ^0.19.0                 ← already present
  └── flutter:
        generate: true                ← turns on gen_l10n

l10n.yaml                              ← new config file (ARB folder, template, output)

lib/l10n/
  app_en.arb                           ← English template, carries @-metadata
  app_es.arb                           ← Spanish (any region)
  app_pt_BR.arb                        ← Portuguese — Brazil flavor specifically
  app_fr.arb                           ← French
  app_de.arb                           ← German
  app_ru.arb                           ← Russian

lib/core/i18n/
  supported_locales.dart               ← single source of truth: const list of 6 Locales
  locale_storage.dart                  ← reads/writes preferred locale to SharedPreferences
  locale_provider.dart                 ← Riverpod StateNotifier: current Locale + setLocale()
  error_messages.dart                  ← translateApiError(BuildContext, ApiResponse) helper
  build_context_ext.dart               ← `context.l10n` extension alias

lib/main.dart                          ← updated:
                                          MaterialApp.localizationsDelegates
                                          MaterialApp.supportedLocales
                                          MaterialApp.locale = ref.watch(localeProvider)
```

The generated `AppLocalizations` class lives in `.dart_tool/flutter_gen/gen_l10n/` (build artifact, gitignored — standard).

A short alias extension keeps call sites readable:
```dart
extension L on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
```
So code reads `context.l10n.loginEmailLabel` instead of `AppLocalizations.of(context)!.loginEmailLabel`.

---

## Locale resolution flow

The locale shown to the user is decided by this chain, top wins:

1. **User's saved preference** (SharedPreferences) — if explicitly chosen in Settings
2. **Device locale** — if it matches a supported locale
3. **Device locale's language code only** — e.g. `fr_CA` → `fr`
4. **English (`en`)** — hard fallback

### Backend sync (preferred_language)

When the user changes language in Settings:
1. Write to SharedPreferences immediately (UI updates synchronously via `MaterialApp.locale = ref.watch(localeProvider)`)
2. Background `PATCH /v1/users/me` with `{"preferred_language": "es"}`
3. PATCH failures are logged but don't roll back the local change

On app launch, inside `AuthNotifier._init` after `getCurrentUser` returns:
- If `user.preferredLanguage != null` and differs from the current local preference, call `localeProvider.setLocale(user.preferredLanguage)` — **backend wins** (the user may have changed language on another device since last launch).

### Backend dependency

New nullable `preferred_language` field (BCP 47 short form — `"en"`, `"es"`, `"pt-BR"`, `"fr"`, `"de"`, `"ru"`) on the User schema:
- Returned by `/v1/auth/*` and `/v1/users/me`
- Accepted by `PATCH /v1/users/me`

**Frontend ships with graceful degradation.** If the backend hasn't deployed the field yet, the frontend detects `user.preferredLanguage == null`, skips the backend-wins step, and operates local-only. The day the backend adds the field, sync starts working with no client changes.

---

## ARB layout & translation workflow

### Key naming
`lowerCamelCase`, scoped by feature: `screenElementPurpose`.

```
loginEmailLabel
loginPasswordHint
chatSendButton
matchesEmptyState
errorEmailExists
errorRateLimited
settingsLanguageTitle
```

Names must be self-documenting so translators understand context without seeing the screen. Avoid `welcome1`, `button2`.

### Template file
`app_en.arb` carries metadata; other files don't:

```json
{
  "@@locale": "en",
  "loginEmailLabel": "Email",
  "@loginEmailLabel": {
    "description": "Label above the email field on the login screen"
  },
  "matchesCount": "{count, plural, =0{No matches yet} =1{1 match} other{{count} matches}}",
  "@matchesCount": {
    "description": "Match counter on the matches tab",
    "placeholders": {
      "count": {"type": "int"}
    }
  }
}
```

ICU `plural` and `select` handle "1 match" vs "5 matches" and gendered forms cleanly across all 6 languages.

### Initial state
This spec's implementation commits:
- `app_en.arb` populated with every Phase 0 string
- The other 5 ARBs as English copies marked `// TODO: translate`

Real translations get swapped in file-by-file as they arrive. The system works end-to-end immediately; the user just sees English in every language slot until real translations land.

### Translation source (decided later, not part of this spec)

The ARB format is supported by every translation platform — Crowdin, Lokalise, Phrase. Three realistic paths the project might take:
1. **Human translator** — export ARBs to a translation platform, native speakers translate, re-import. Best quality, real cost.
2. **AI first pass + human review** — GPT-4 / DeepL produces draft, native speaker proofreads. Cheaper, acceptable for a social app.
3. **AI only** — fast, free, low quality. Not recommended for a social product where users judge polish.

This spec does not commit to a source. It commits to a format and structure that supports all three.

---

## Backend integration

### Two touchpoints with the backend

#### 1. `preferred_language` field on User
- New nullable `String?` field on `User` model
- Added to `User.fromJson` (read `preferred_language`), `User.toJson`, `User.copyWith`
- `AuthService.updatePreferredLanguage(String code)` calls `PATCH /v1/users/me` with `{"preferred_language": code}`
- Backend team must add the field to schema + accept it in PATCH endpoint

#### 2. Error code → translated string mapping
Centralized in `lib/core/i18n/error_messages.dart`:

```dart
String translateApiError(BuildContext context, ApiResponse r) {
  final l10n = context.l10n;
  switch (r.errorCode) {
    case 'INVALID_CREDENTIALS': return l10n.errorInvalidCredentials;
    case 'EMAIL_EXISTS':        return l10n.errorEmailExists;
    case 'RATE_LIMITED':        return l10n.errorRateLimited;
    case 'AUTH_LOST':           return l10n.errorAuthLost;
    // …extend as we discover codes
  }
  return r.error ?? l10n.errorGeneric;
}
```

### ApiClient becomes locale-agnostic

Today `ApiClient` builds user-facing strings ("Slow down — too many requests…", "Your session has ended…") directly. As part of this work, those strings move out of `ApiClient` and into the ARB files. `ApiClient` only sets `errorCode` and a fallback English `error`. The UI layer translates via `translateApiError(context, response)`.

This is a small refactor: ~12 snackbar call sites already display `response.error` — they need to route through `translateApiError` instead. The change is mechanical and unifies error display across the app.

---

## Settings UI: language picker

One new entry in `lib/screens/settings/settings_screen.dart`:

```
🌐 Language               English  >
```

Tapping opens a full-screen route (consistent with how Settings handles other multi-option choices) showing one `RadioListTile` per supported language. Each row displays the language's name **in that language** — a Spanish speaker recognizes "Español" but might not recognize "Spanish":

```
○ English
● Español                              ← current selection
○ Português (Brasil)
○ Français
○ Deutsch
○ Русский
─────────────────────────────────
○ Use device language                   ← clears the override
```

The "Use device language" row maps to clearing the saved preference; the resolution chain then falls back to the device locale. This is essential UX — once a user picks an override they need a way to undo it without knowing what their device locale string is.

On selection: `localeProvider.setLocale(picked)` → SharedPreferences write → background PATCH to backend → app rebuilds in the new locale.

---

## Migration of existing hardcoded strings

The codebase has hundreds of hardcoded strings. Migrating them all at once would touch nearly every file. Phased approach:

### Phase 0 — Infrastructure (this spec)
Ship the system in Sections 1-5 with ARB files populated only for **app-shell strings** every user sees on first launch:
- App name, tagline
- Welcome / login / register screens
- Settings screen, including the new Language picker
- Error-code map (auth + rate-limit messages)
- Bottom-nav labels (Home, Matches, Chat, Profile, Settings)

Estimated: 50–80 keys. Enough to prove the system end-to-end in all 6 languages.

### Phase 1 — Onboarding & profile (own spec)
SocialProfileCompletionFlow, registration steps, profile editor, photo upload prompts. ~50 more keys.

### Phase 2 — Discovery & matching (own spec)
Home/swipe screen, match dialog, matches list, match detail. ~30 keys.

### Phase 3 — Chat (own spec)
Conversation list, chat screen, message actions menu, sticker picker, voice/video recording UI. ~60 keys.

### Phase 4 — Edges (own spec)
Permission dialogs, error states, empty states.

### Migration rules
- **Never partially migrate a screen.** If a screen has 12 strings, migrate all 12 in one PR. Mixed-language screens are worse than fully-English screens.
- **Phase 1+ work introduces a CI grep guard** that fails on `const Text('` (literal English strings) inside files in a `MIGRATED_SCREENS` list. Prevents regressions where someone adds a hardcoded string to a screen that was already migrated. Not part of Phase 0 since no screens are migrated yet — but designing for it now informs the file structure.

This spec's implementation = Phase 0 only.

---

## Testing

### Layer 1 — Compile-time (free)
The codegen catches missing keys: if `app_en.arb` has `welcomeHeader` and you call `context.l10n.welcomeHeader`, fine. Rename or remove it and every call site is a build error. No runtime checks needed.

### Layer 2 — ARB completeness test (single tiny test)
```dart
test('every key in app_en.arb has a translation in all other ARBs', () {
  final en = readArb('app_en.arb');
  for (final lang in ['es', 'pt', 'fr', 'de', 'ru']) {
    final other = readArb('app_$lang.arb');
    expect(other.keys.toSet(), equals(en.nonMetadataKeys.toSet()),
        reason: 'app_$lang.arb is missing or has extra keys vs en');
  }
});
```
Runs in milliseconds. Catches "translator missed one" and "you added a key but only to English."

### Layer 3 — Locale resolution unit tests
`test/core/i18n/locale_provider_test.dart` covers the chain from the Locale Resolution Flow section:
- Saved preference wins over device locale
- Device locale wins when no preference saved
- Unsupported device locale falls back to language code (`fr_CA` → `fr`)
- Unsupported language falls back to English
- `setLocale(null)` clears preference, reverts to device locale
- Backend `preferredLanguage` on app launch overrides local when different

### Manual visual QA (not automated)
Run the app in each of the 6 languages on the iPhone 15 Pro simulator, eyeball every Phase 0 screen for layout breakage. **German and Russian are the usual offenders** — German strings are ~30% longer than English; Russian Cyrillic can break tight letter-spacing.

Use the iOS simulator's `Settings → General → Language & Region` to switch device language for testing without code changes.

---

## Out of scope

These are intentionally not addressed by this spec:

- **RTL languages (Arabic, Hebrew, Urdu).** Would require a layout audit pass across every screen. Revisit when those languages are added.
- **Machine translation of user-generated content** (bio, messages). A separate Google Translate / DeepL API integration; its own product decision.
- **Locale-aware date / number / currency formatting beyond what `intl` already does.** Already adequate for current screens.
- **Phases 1-4 screen migrations.** Each gets its own spec when prioritized.
- **The translation source itself** — human vs AI vs hybrid. A workflow/budget decision, not an architecture decision.

---

## Backend team dependencies

| Item | Owner | Blocking? |
|---|---|---|
| Add nullable `preferred_language` (ISO 639-1) to User schema | Backend | No — frontend degrades gracefully |
| Accept `preferred_language` in `PATCH /v1/users/me` | Backend | No — frontend skips sync if 400 |
| Return `preferred_language` on auth endpoints + `/users/me` | Backend | No |

All three are non-blocking. Frontend can ship Phase 0 today with local-only persistence; backend sync activates the moment the backend deploys the field.

---

## Open questions

None. All decisions are settled.
