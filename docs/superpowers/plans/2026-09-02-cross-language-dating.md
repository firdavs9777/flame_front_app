# Cross-Language Dating Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Flame an app for meeting people you could not otherwise talk to — declared languages, a ranking component that rewards complementarity, and UI that shows the premise in the first thirty seconds — to answer App Review's Guideline 4.3(b) rejection.

**Architecture:** Two capped lists of ISO 639-1 codes on the user (`languagesSpoken`, `languagesLearning`), mirrored catalogues in both repos, a sixth pure component in the existing `rankingService`, and three visibility surfaces. Ranking only — never filtering. Unknown always scores neutral, never last.

**Tech Stack:** Flutter/Dart (app), Node/Express + Mongoose + zod (`flame/` only), `node --test`, `flutter test`.

**Spec:** `docs/superpowers/specs/2026-09-02-cross-language-dating-design.md`

## Global Constraints

- **Backend work touches `flame/` ONLY.** Never `server.js`, `models/User.js` at the repo root, `migrations/`, or anything else belonging to BananaTalk. Verify before every backend commit: `git status --short | awk '{print $2}' | grep -v '^flame/'` must print nothing.
- App repo: `flutter analyze` must be **error-clean** (0 lines matching `error •`). Warnings/infos pre-exist and are acceptable.
- App repo: `flutter test` must be fully green before each commit.
- Backend: run only the named test files. The full 81-file suite takes >10 minutes and times out.
- **No new user-facing English strings** unless the task says so. `test/l10n/arb_parity_test.dart` requires every new key to exist in all 25 base locale ARBs.
- Language display names are **endonyms** — the language's own name, never translated, so no ARB keys are added for them.
- Stored language values are **ISO 639-1 lowercase codes** and are never translated.
- Maximum **3** entries in each of `languagesSpoken` and `languagesLearning`.
- Ranking weights must always sum to exactly 1.0.
- Unknown language data scores **0.50 (neutral)** — never 0, and never below a declared-but-poor match.

## Prior art in BananaTalk — corrected after reading the real app

An earlier draft of this plan was written against a stale copy of
`moment_filter_model.dart` found in `~/Downloads`. The actual app at
`~/Projects/BananaTalk/bananatalk_app` is considerably more developed, and it
overturns two recommendations that draft made. Both corrections are recorded
here so nobody re-derives the wrong conclusion from the wrong file.

### What the real app does

| File | What it establishes |
|---|---|
| `lib/providers/languages_provider.dart` | `GET /languages` (127+ entries) is the source of truth, resolved **network → persisted cache → small hardcoded fallback** |
| `lib/widgets/language_selection/language_picker_screen.dart` | A full-screen picker: search field, "Recommended" section, alphabetical list, A–Z index past 20 results |
| `lib/models/language_model.dart` | `{id, code, name, nativeName, flag}` — flag prefers a client map, falls back to the backend's, then 🌐 |
| `lib/utils/language_flags.dart` | Flag map with **regional variants** (`en-gb`, `en-us`, `es-mx`, `ar-eg`, `ar-lv`) and reasoning in comments |

### Correction 1 — flags are fine; my objection was based on the stale file

The draft said "no flag emoji" because the Downloads copy mapped English to 🇺🇸.
**The real map uses 🇬🇧 for `en`**, carries regional variants so `en-us` and
`en-gb` are distinct, documents contested choices in comments (Levantine Arabic
→ 🇱🇧 as "recognized media standard for a dialect spanning LB/SY/JO/PS"), and
falls back to **🌐** rather than guessing.

That is about as carefully as flags-for-languages can be done. **Adopt it**, and
mirror the map rather than inventing one — consistency across the two products
is worth more than my abstract objection, and 🌐 covers the cases that have no
defensible flag.

### Correction 2 — fetch with a fallback, don't ship a frozen list

The draft said "copy the data, don't call the API", on the grounds that a
network call would add a failure mode to the registration screen App Review
rejected. **`languages_provider.dart` already solves that**, and its resolution
order is the answer:

1. network fetch — result persisted for offline
2. persisted cache from a previous session
3. `kLanguageCatalogFallback` — a deliberately small hardcoded list

The picker can never be empty, so the objection does not survive. This is the
better pattern and Flame should use it.

**But Flame serves its own catalogue.** It fetches
`/flamebackend/v1/languages`, not BananaTalk's `/api/v1/languages`. `CLAUDE.md`
states flame's isolation as a principle and this work is under a standing
instruction to touch nothing outside `flame/`; a shared runtime route would
couple signup to another product's release cycle. Same data, same three-tier
pattern, own endpoint.

### Correction 3 — a picker screen, not a chip grid

The draft put forty language chips inline in registration step 4. With 127+
languages that does not scale, and it is also *worse* for the friction concern
that shaped the design: forty chips is a wall, whereas one tappable row reading
"English, 한국어" is barely an addition to the step at all.

Mirror `language_picker_screen.dart` — search, Recommended, alphabetical.
Recommended seeds from the same ten codes their app uses
(`en ko ja zh es fr de it pt ru`), plus the device locale.

---

### Task 1: Language model, flags and offline fallback

**Files:**
- Create: `lib/core/languages/language.dart`
- Create: `lib/core/languages/language_flags.dart`
- Create: `lib/core/languages/language_fallback.dart`
- Test: `test/core/languages/language_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class Language {String code; String name; String nativeName; String flag;}`, `Language.fromJson`, `LanguageFlags.getFlag(String)`, `kLanguageFallback` (List<Language>), `kRecommendedCodes` (List<String>).

- [ ] **Step 1: Write the failing test**

```dart
// test/core/languages/language_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/languages/language.dart';
import 'package:flame/core/languages/language_fallback.dart';
import 'package:flame/core/languages/language_flags.dart';

void main() {
  group('Language.fromJson', () {
    test('parses the GET /languages shape', () {
      final l = Language.fromJson({
        'code': 'ko', 'name': 'Korean', 'nativeName': '한국어',
      });

      expect(l.code, 'ko');
      expect(l.name, 'Korean');
      expect(l.nativeName, '한국어');
    });

    test('falls back to the English name when nativeName is missing', () {
      // The backend has entries with an empty nativeName. A blank label in a
      // picker is worse than an English one.
      final l = Language.fromJson({'code': 'xx', 'name': 'Example'});
      expect(l.nativeName, 'Example');
    });

    test('a malformed entry throws rather than becoming a blank row', () {
      expect(() => Language.fromJson({'name': 'No code'}), throwsA(anything));
    });
  });

  group('flags', () {
    test('English is 🇬🇧, matching the BananaTalk map', () {
      // NOT 🇺🇸. Mirrored deliberately so the two products agree.
      expect(LanguageFlags.getFlag('en'), '🇬🇧');
    });

    test('regional variants resolve before the base language', () {
      expect(LanguageFlags.getFlag('en-us'), '🇺🇸');
      expect(LanguageFlags.getFlag('en-gb'), '🇬🇧');
    });

    test('an unknown region falls back to the base language', () {
      expect(LanguageFlags.getFlag('es-cl'), LanguageFlags.getFlag('es'));
    });

    test('anything unrecognised is the globe, never a wrong flag', () {
      expect(LanguageFlags.getFlag('zz'), '🌐');
      expect(LanguageFlags.getFlag(''), '🌐');
    });
  });

  group('offline fallback', () {
    test('is small but never empty', () {
      // The picker must work on a first-ever launch with no network. This is
      // the floor, not the catalogue.
      expect(kLanguageFallback, isNotEmpty);
      expect(kLanguageFallback.length, lessThan(30));
    });

    test('every fallback entry has a code and a label', () {
      for (final l in kLanguageFallback) {
        expect(l.code, matches(RegExp(r'^[a-z]{2}$')));
        expect(l.nativeName.trim(), isNotEmpty);
      }
    });

    test('recommended codes are all present in the fallback', () {
      // Otherwise an offline user sees a Recommended section with gaps.
      for (final code in kRecommendedCodes) {
        expect(kLanguageFallback.any((l) => l.code == code), isTrue,
            reason: '$code is recommended but missing offline');
      }
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/languages/language_test.dart`
Expected: FAIL — `language.dart` does not exist.

- [ ] **Step 3: Write the model**

```dart
// lib/core/languages/language.dart
import 'package:flutter/foundation.dart';

import 'package:flame/core/languages/language_flags.dart';

/// One language, as served by `GET /flamebackend/v1/languages`.
///
/// Mirrors BananaTalk's `models/language_model.dart` so the two products
/// describe the same thing the same way.
@immutable
class Language {
  const Language({
    required this.code,
    required this.name,
    required this.nativeName,
  });

  /// ISO 639-1, lowercase. The stored value, never translated — translating a
  /// stored value breaks every record and every match at once.
  final String code;

  /// The English name. Used for SEARCH, so someone can type "Korean" as well
  /// as 한국어.
  final String name;

  /// The language's own name — what the picker and profiles display.
  final String nativeName;

  /// Country flag, or 🌐 when none is defensible.
  String get flag => LanguageFlags.getFlag(code);

  factory Language.fromJson(Map<String, dynamic> json) {
    final code = json['code'] as String?;
    if (code == null || code.isEmpty) {
      throw ArgumentError('language entry has no code: $json');
    }
    final name = (json['name'] as String?)?.trim() ?? code;
    final native = (json['nativeName'] as String?)?.trim();

    return Language(
      code: code.toLowerCase(),
      name: name,
      // An empty nativeName is real in the backend data. A blank row in a
      // picker is worse than an English one.
      nativeName: (native == null || native.isEmpty) ? name : native,
    );
  }

  @override
  bool operator ==(Object other) => other is Language && other.code == code;

  @override
  int get hashCode => code.hashCode;
}
```

- [ ] **Step 4: Mirror the flag map**

Copy `~/Projects/BananaTalk/bananatalk_app/lib/utils/language_flags.dart`'s
`flags` map and `getFlag` resolution into
`lib/core/languages/language_flags.dart`, keeping its comments. Do not retype
it — copy the file and strip everything Flame does not use (`_nameToCode`, the
exam helpers). Keep `getRecommendedCodes()` as `kRecommendedCodes`.

Header the file with:

```dart
/// Flag emoji per language, MIRRORED from BananaTalk's
/// lib/utils/language_flags.dart so the two products never disagree about
/// what 한국어 looks like in a list.
///
/// Flags mark countries, not languages, which is a real objection — but this
/// map handles it about as well as it can be: 🇬🇧 for `en` rather than 🇺🇸,
/// regional variants so en-us and en-gb are distinct, reasoning recorded for
/// the contested ones, and 🌐 rather than a guess for anything unresolved.
```

- [ ] **Step 5: Write the offline fallback**

```dart
// lib/core/languages/language_fallback.dart
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
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/core/languages/language_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 7: Verify analyze and commit**

Run: `flutter analyze 2>&1 | grep -c "error •"` → `0`

```bash
git add lib/core/languages test/core/languages/language_test.dart
git commit -m "feat(languages): the model, mirrored from BananaTalk

Same shape, same flag map, same recommended ten, so the two products never
disagree about what a language looks like in a list.

Flags mark countries rather than languages, which is a real objection --
but this map handles it about as well as it can be: 🇬🇧 for en rather than
🇺🇸, regional variants so en-us and en-gb differ, reasoning recorded for
contested cases, and 🌐 rather than a guess when nothing fits.

The fallback list is a floor, not the catalogue: 17 entries so a
first-ever launch with no network still has a working picker. The real
list is 127+ from the server."
```

---

### Task 2: Flame's own /languages endpoint, and the three-tier provider

**Files:**
- Create: `flame/config/languages.js` (backend)
- Create: `flame/routes/languages.js` (backend)
- Modify: `flame/index.js` (register the route)
- Create: `flame/__tests__/languagesRoute.test.js` (backend)
- Create: `lib/providers/languages_provider.dart` (app)
- Test: `test/providers/languages_provider_test.dart` (app)

**Interfaces:**
- Consumes: `Language`, `kLanguageFallback` from Task 1.
- Produces: `GET /flamebackend/v1/languages` → `{success, data: [{code, name, nativeName}]}`; `languageCatalogProvider` (FutureProvider<List<Language>>); `isLanguageCode(code)` for Task 3's validation.

**Flame serves its own catalogue.** Not BananaTalk's `/api/v1/languages`:
`CLAUDE.md` states flame's isolation as a principle, and coupling signup to
another product's release cycle is exactly what it warns about. Same data, own
endpoint.

- [ ] **Step 1: Generate the backend catalogue from BananaTalk's data**

Save as `flame/scripts/gen-languages.js` and run it once. It derives the list
from `_data/languages.json` — 182 entries with a `nativeName` column — rather
than anyone retyping 한국어 and العربية by hand.

```javascript
// flame/scripts/gen-languages.js
//
// Regenerates flame/config/languages.js from the shared language data.
// Run manually; the output is committed.
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '../../_data/languages.json');
const OUT = path.join(__dirname, '../config/languages.js');

const all = JSON.parse(fs.readFileSync(SRC, 'utf8'));

const entries = all
  .filter((l) => /^[a-z]{2}$/.test(l.code))
  .map((l) => ({
    code: l.code,
    name: String(l.name || l.code).trim(),
    // Empty nativeName is real in this data. Falling back to the English name
    // beats a blank row in a picker.
    nativeName: String(l.nativeName || l.name || l.code).trim(),
  }))
  .sort((a, b) => a.name.localeCompare(b.name));

const body = entries
  .map((e) => `  { code: '${e.code}', name: ${JSON.stringify(e.name)}, nativeName: ${JSON.stringify(e.nativeName)} },`)
  .join('\n');

fs.writeFileSync(OUT, `// GENERATED by flame/scripts/gen-languages.js from _data/languages.json.
// Do not edit by hand -- re-run the script.
//
// Flame serves this itself at GET /flamebackend/v1/languages rather than
// pointing the app at BananaTalk's /api/v1/languages. CLAUDE.md states
// flame's isolation as a principle, and coupling signup to another product's
// release cycle is what it warns about. Same data, own endpoint.
const LANGUAGES = Object.freeze([
${body}
].map(Object.freeze));

const LANGUAGE_CODES = Object.freeze(LANGUAGES.map((l) => l.code));
const _set = new Set(LANGUAGE_CODES);

/** Whether \`code\` is one this app knows. Case-insensitive. */
function isLanguageCode(code) {
  if (typeof code !== 'string') return false;
  return _set.has(code.toLowerCase());
}

module.exports = { LANGUAGES, LANGUAGE_CODES, isLanguageCode };
`);

console.log(`generated ${entries.length} languages`);
```

Run: `cd ~/Projects/BananaTalk/backend && node flame/scripts/gen-languages.js`
Expected: `generated 180+ languages` (182 minus any non-two-letter codes).

- [ ] **Step 2: Write the failing route test**

```javascript
// flame/__tests__/languagesRoute.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

process.env.FLAME_SPACES_BUCKET = 't';
process.env.SPACES_ENDPOINT = 'e';
process.env.DO_SPACES_KEY = 'k';
process.env.DO_SPACES_SECRET = 's';

const { buildApp } = require('./helpers/app');
const { isLanguageCode, LANGUAGES } = require('../config/languages');

const BASE = '/flamebackend/v1';

test('GET /languages returns the catalogue without authentication', async () => {
  // The picker is on the REGISTRATION screen — there is no token yet.
  const res = await request(buildApp()).get(`${BASE}/languages`).expect(200);

  assert.equal(res.body.success, true);
  assert.ok(Array.isArray(res.body.data));
  assert.ok(res.body.data.length > 100, 'the catalogue, not the fallback');
});

test('every entry carries a code, a name and a nativeName', async () => {
  const res = await request(buildApp()).get(`${BASE}/languages`).expect(200);

  for (const l of res.body.data) {
    assert.match(l.code, /^[a-z]{2}$/);
    assert.ok(l.name && l.name.length, `${l.code} has no name`);
    assert.ok(l.nativeName && l.nativeName.length, `${l.code} has no nativeName`);
  }
});

test('isLanguageCode agrees with the served list', () => {
  for (const l of LANGUAGES) assert.equal(isLanguageCode(l.code), true);
  assert.equal(isLanguageCode('zz'), false);
  assert.equal(isLanguageCode(null), false);
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ~/Projects/BananaTalk/backend && node --test flame/__tests__/languagesRoute.test.js`
Expected: FAIL — 404, the route does not exist.

- [ ] **Step 4: Add the route**

```javascript
// flame/routes/languages.js
const express = require('express');
const { LANGUAGES } = require('../config/languages');

const router = express.Router();

// PUBLIC, deliberately: the language picker is on the registration screen, so
// there is no token yet. The payload is a static, non-sensitive list.
router.get('/', (_req, res) => {
  res.json({ success: true, data: LANGUAGES });
});

module.exports = router;
```

In `flame/index.js`, beside the other `router.use` lines:

```javascript
router.use('/languages', require('./routes/languages'));
```

- [ ] **Step 5: Run test to verify it passes**

Run: `node --test flame/__tests__/languagesRoute.test.js`
Expected: PASS, 3 tests.

- [ ] **Step 6: Verify blast radius and commit the backend**

```bash
git status --short | awk '{print $2}' | grep -v '^flame/'   # must print nothing
git add flame/config/languages.js flame/routes/languages.js flame/index.js \
        flame/scripts/gen-languages.js flame/__tests__/languagesRoute.test.js
git commit -m "feat(flame): serve the language catalogue

Generated from the shared _data/languages.json rather than retyped, and
served from flame's own route rather than pointing the app at BananaTalk's
/api/v1/languages -- CLAUDE.md states flame's isolation as a principle, and
coupling signup to another product's release cycle is what it warns about.

Public, deliberately: the picker sits on the registration screen, so there
is no token yet, and the payload is a static non-sensitive list."
```

- [ ] **Step 7: Write the failing provider test**

```dart
// test/providers/languages_provider_test.dart
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
```

- [ ] **Step 8: Run test to verify it fails**

Run: `flutter test test/providers/languages_provider_test.dart`
Expected: FAIL — `languages_provider.dart` does not exist.

- [ ] **Step 9: Write the provider**

```dart
// lib/providers/languages_provider.dart
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
```

- [ ] **Step 10: Run test to verify it passes**

Run: `flutter test test/providers/languages_provider_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 11: Full suite, analyze, commit**

```bash
flutter test 2>&1 | tail -3
flutter analyze 2>&1 | grep -c "error •"   # 0

git add lib/providers/languages_provider.dart test/providers/languages_provider_test.dart
git commit -m "feat(languages): fetch the catalogue, with two floors under it

Network, then the persisted copy, then a bundled list -- the same ladder
BananaTalk's languages_provider uses, and the reason it is safe to put a
fetch behind the registration screen App Review rejected. There is no path
where the picker is empty; worst case it is short.

A 200 carrying an empty array is treated as a failure rather than an
answer, so a bad deploy cannot overwrite a good cache with nothing. One
malformed entry is skipped rather than costing the other 180."
```

---

### Task 3: Backend user fields, validation and wire shape

**Files:**
- Modify: `flame/models/User.js` (add two fields beside `interests`, around line 114)
- Modify: `flame/services/userService.js` (the `PATCHABLE` list, around line 114)
- Modify: `flame/routes/users.js` (the `updateSchema` zod object)
- Modify: `flame/services/discoveryService.js` (`toDiscoverUser`)
- Test: `flame/__tests__/userLanguages.test.js` (create)

**Interfaces:**
- Consumes: `isLanguageCode`, `LANGUAGE_CODES` from Task 2.
- Produces: `user.languagesSpoken` / `user.languagesLearning` (arrays of ISO codes) readable by Task 5's ranker; wire fields `languages_spoken` / `languages_learning` consumed by Task 4.

- [ ] **Step 1: Write the failing test**

```javascript
// flame/__tests__/userLanguages.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const dbHelper = require('./helpers/db');

async function setup() {
  await dbHelper.start();
  process.env.FLAME_SPACES_BUCKET = 't';
  process.env.SPACES_ENDPOINT = 'sfo3.digitaloceanspaces.com';
  process.env.DO_SPACES_KEY = 'k';
  process.env.DO_SPACES_SECRET = 's';
  ['../db', '../models/User', '../services/userService'].forEach((p) => {
    try { delete require.cache[require.resolve(p)]; } catch {}
  });
  const { connect } = require('../db');
  await connect();
  return {
    User: require('../models/User'),
    userService: require('../services/userService'),
  };
}

async function teardown() {
  const { close } = require('../db');
  await close();
  await dbHelper.stop();
}

let seq = 0;
async function makeUser(User, over = {}) {
  seq += 1;
  return User.create({
    email: `lang${seq}@x.com`,
    passwordHash: 'hash',
    name: 'Test User',
    age: 25,
    gender: 'female',
    lookingFor: 'male',
    ...over,
  });
}

test('both language lists default to empty', async (t) => {
  const { User } = await setup();
  t.after(teardown);

  const user = await makeUser(User);

  assert.deepEqual(user.languagesSpoken, []);
  assert.deepEqual(user.languagesLearning, []);
});

test('a legacy document with no language fields reads as empty', async (t) => {
  // Every account predates these fields. Inserted through the raw driver so
  // Mongoose defaults cannot paper over what production actually holds.
  const { User } = await setup();
  t.after(teardown);

  const res = await User.collection.insertOne({
    email: 'legacy-lang@x.com', passwordHash: 'h', name: 'Legacy',
    age: 30, gender: 'female', lookingFor: 'male', isDeleted: false,
  });

  const user = await User.findById(res.insertedId).lean();
  assert.deepEqual(user.languagesSpoken ?? [], []);
  assert.deepEqual(user.languagesLearning ?? [], []);
});

test('updateProfile stores both lists', async (t) => {
  const { User, userService } = await setup();
  t.after(teardown);
  const user = await makeUser(User);

  const updated = await userService.updateProfile(user._id.toString(), {
    languagesSpoken: ['ko', 'en'],
    languagesLearning: ['es'],
  });

  assert.deepEqual(updated.languagesSpoken, ['ko', 'en']);
  assert.deepEqual(updated.languagesLearning, ['es']);
});

test('more than three entries is rejected', async (t) => {
  const { User } = await setup();
  t.after(teardown);

  await assert.rejects(
    () => makeUser(User, { languagesSpoken: ['en', 'ko', 'es', 'fr'] }),
    /languagesSpoken/,
  );
});

test('an unknown code is rejected', async (t) => {
  // The catalogue is the contract. A code the app cannot render is a code
  // nothing can match on either.
  const { User } = await setup();
  t.after(teardown);

  await assert.rejects(
    () => makeUser(User, { languagesSpoken: ['zz'] }),
    /languagesSpoken/,
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/firdavsmutalipov/Projects/BananaTalk/backend && node --test flame/__tests__/userLanguages.test.js`
Expected: FAIL — `languagesSpoken` is undefined, so the first assertion fails with `undefined !== []`.

- [ ] **Step 3: Add the model fields**

In `flame/models/User.js`, immediately after the `interests` line (~114):

```javascript
  // Languages, the premise of the app rather than a profile decoration.
  //
  // ISO 639-1 codes validated against flame/config/languages.js — the app
  // renders each under its own endonym, so a code it cannot render is a code
  // nothing can match on either.
  //
  // Capped at three each: the cap is what keeps a "languages" list from
  // becoming a wishlist, and it bounds the ranker's comparison cost.
  //
  // Both default to [] and every consumer treats empty as UNKNOWN, never as
  // "speaks nothing" — every account predates these fields.
  languagesSpoken: {
    type: [String],
    default: [],
    validate: {
      validator: (v) => v.length <= 3 && v.every(isLanguageCode),
      message: 'languagesSpoken must be at most 3 known language codes',
    },
  },
  languagesLearning: {
    type: [String],
    default: [],
    validate: {
      validator: (v) => v.length <= 3 && v.every(isLanguageCode),
      message: 'languagesLearning must be at most 3 known language codes',
    },
  },
```

And at the top of the file, beside the other requires:

```javascript
const { isLanguageCode } = require('../config/languages');
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/firdavsmutalipov/Projects/BananaTalk/backend && node --test flame/__tests__/userLanguages.test.js`
Expected: PASS, 5 tests.

- [ ] **Step 5: Allow the fields through the profile update**

In `flame/services/userService.js`, add both names to the `PATCHABLE` array (~line 114, the array containing `'minAge', 'maxAge', 'maxDistance'`... find the profile-field list, which contains `'name'`, `'bio'`, `'interests'`):

```javascript
  'languagesSpoken', 'languagesLearning',
```

In `flame/routes/users.js`, add to `updateSchema`:

```javascript
  languagesSpoken: z.array(z.string().trim().toLowerCase()).max(3).optional(),
  languagesLearning: z.array(z.string().trim().toLowerCase()).max(3).optional(),
```

- [ ] **Step 6: Add the fields to the discovery wire shape**

In `flame/services/discoveryService.js`, inside `toDiscoverUser`, beside `interests`:

```javascript
    // snake_case to match the Flutter User.fromJson parser.
    languages_spoken: u.languagesSpoken || [],
    languages_learning: u.languagesLearning || [],
```

- [ ] **Step 7: Run the affected suites**

Run:
```bash
cd /Users/firdavsmutalipov/Projects/BananaTalk/backend
node --test flame/__tests__/userLanguages.test.js flame/__tests__/users.test.js \
  flame/__tests__/userModel.test.js flame/__tests__/userService.test.js \
  flame/__tests__/discoverFilters.test.js
```
Expected: all PASS, 0 fail.

- [ ] **Step 8: Verify blast radius and commit**

```bash
git status --short | awk '{print $2}' | grep -v '^flame/'   # must print nothing
git add flame/models/User.js flame/services/userService.js flame/routes/users.js \
        flame/services/discoveryService.js flame/__tests__/userLanguages.test.js
git commit -m "feat(flame): declared languages on the user

Two capped lists of ISO codes, validated against the catalogue: a code the
app cannot render is a code nothing can match on either.

Both default to [] and every consumer treats empty as UNKNOWN rather than
'speaks nothing' — every existing account predates these fields, and a test
inserts through the raw driver to prove a legacy document reads correctly
rather than trusting Mongoose defaults to paper over it."
```

---

### Task 4: App model and service plumbing

**Files:**
- Modify: `lib/models/user.dart` (fields, `fromJson`, `copyWith`)
- Modify: `lib/services/user_service.dart` (`updateProfile` body)
- Modify: `lib/providers/user_provider.dart` (pass-through)
- Test: `test/models/user_languages_test.dart` (create)

**Interfaces:**
- Consumes: wire fields `languages_spoken` / `languages_learning` from Task 3.
- Produces: `User.languagesSpoken`, `User.languagesLearning` (`List<String>`), consumed by Tasks 6 and 7.

- [ ] **Step 1: Write the failing test**

```dart
// test/models/user_languages_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/models/user.dart';

Map<String, dynamic> _json(Map<String, dynamic> extra) => {
      'id': 'u1',
      'name': 'Alex',
      'age': 28,
      'photos': <dynamic>[],
      ...extra,
    };

void main() {
  test('parses both language lists', () {
    final user = User.fromJson(_json({
      'languages_spoken': ['ko', 'en'],
      'languages_learning': ['es'],
    }));

    expect(user.languagesSpoken, ['ko', 'en']);
    expect(user.languagesLearning, ['es']);
  });

  test('absent fields read as empty, not null', () {
    // Every existing account, and every response from a server that has not
    // deployed yet. Empty means UNKNOWN everywhere downstream.
    final user = User.fromJson(_json({}));

    expect(user.languagesSpoken, isEmpty);
    expect(user.languagesLearning, isEmpty);
  });

  test('a null list reads as empty rather than throwing', () {
    final user = User.fromJson(_json({
      'languages_spoken': null,
      'languages_learning': null,
    }));

    expect(user.languagesSpoken, isEmpty);
    expect(user.languagesLearning, isEmpty);
  });

  test('copyWith carries the lists through', () {
    final user = User.fromJson(_json({'languages_spoken': ['ko']}));
    final copy = user.copyWith(languagesLearning: ['ja']);

    expect(copy.languagesSpoken, ['ko'], reason: 'untouched fields survive');
    expect(copy.languagesLearning, ['ja']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/user_languages_test.dart`
Expected: FAIL — `The getter 'languagesSpoken' isn't defined for the class 'User'`.

- [ ] **Step 3: Add the fields to the model**

In `lib/models/user.dart`, beside `interests`:

```dart
  /// Languages this person speaks, as ISO 639-1 codes.
  ///
  /// Empty means UNKNOWN, never "speaks nothing" — every account created
  /// before this feature has an empty list, and the ranker scores unknown
  /// neutrally rather than last.
  final List<String> languagesSpoken;

  /// Languages this person is learning, as ISO 639-1 codes.
  final List<String> languagesLearning;
```

In the constructor parameter list:

```dart
    this.languagesSpoken = const [],
    this.languagesLearning = const [],
```

In `fromJson`, beside the `interests` line:

```dart
      languagesSpoken: List<String>.from(json['languages_spoken'] ?? []),
      languagesLearning: List<String>.from(json['languages_learning'] ?? []),
```

In `copyWith`, add the two parameters and pass them:

```dart
    List<String>? languagesSpoken,
    List<String>? languagesLearning,
```

```dart
      languagesSpoken: languagesSpoken ?? this.languagesSpoken,
      languagesLearning: languagesLearning ?? this.languagesLearning,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/user_languages_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Send the lists on profile update**

In `lib/services/user_service.dart`, find `updateProfile` and add two optional named parameters plus their body entries:

```dart
    List<String>? languagesSpoken,
    List<String>? languagesLearning,
```

```dart
      if (languagesSpoken != null) 'languagesSpoken': languagesSpoken,
      if (languagesLearning != null) 'languagesLearning': languagesLearning,
```

In `lib/providers/user_provider.dart`, mirror the same two optional parameters on the `updateProfile` wrapper and forward them.

- [ ] **Step 6: Run the full app suite**

Run: `flutter test 2>&1 | tail -3` and `flutter analyze 2>&1 | grep -c "error •"`
Expected: all tests pass; analyze prints `0`.

- [ ] **Step 7: Commit**

```bash
git add lib/models/user.dart lib/services/user_service.dart \
        lib/providers/user_provider.dart test/models/user_languages_test.dart
git commit -m "feat(languages): carry declared languages through the app model

Absent and null both read as an empty list, and empty means UNKNOWN rather
than 'speaks nothing' — every existing account has no language data, as does
every response from a server that has not deployed yet."
```

---

### Task 5: The ranking component

**Files:**
- Modify: `flame/services/rankingService.js` (WEIGHTS, new `languageScore`, `scoreCandidate`)
- Test: `flame/__tests__/languageRanking.test.js` (create)

**Interfaces:**
- Consumes: `user.languagesSpoken` / `languagesLearning` from Task 3.
- Produces: `ranking.languageScore(viewer, candidate)` returning 0..1; `WEIGHTS.language`.

- [ ] **Step 1: Write the failing test**

```javascript
// flame/__tests__/languageRanking.test.js
const test = require('node:test');
const assert = require('node:assert/strict');

process.env.FLAME_SPACES_BUCKET = 't';
process.env.SPACES_ENDPOINT = 'sfo3.digitaloceanspaces.com';
process.env.DO_SPACES_KEY = 'k';
process.env.DO_SPACES_SECRET = 's';

const ranking = require('../services/rankingService');

const who = (spoken, learning) => ({
  languagesSpoken: spoken,
  languagesLearning: learning,
});

test('a mutual exchange scores highest', () => {
  // I speak English and am learning Korean; you speak Korean and are
  // learning English. This is the pairing the whole app exists for.
  const score = ranking.languageScore(
    who(['en'], ['ko']),
    who(['ko'], ['en']),
  );
  assert.equal(score, 1.0);
});

test('they speak what I am learning beats me speaking what they are learning', () => {
  // The deck is ordered FOR THE VIEWER: someone who can teach me is worth
  // more to me than someone who wants what I already have.
  const theyTeach = ranking.languageScore(who(['en'], ['ko']), who(['ko'], []));
  const iTeach = ranking.languageScore(who(['en'], ['ko']), who(['fr'], ['en']));

  assert.equal(theyTeach, 0.85);
  assert.equal(iTeach, 0.75);
  assert.ok(theyTeach > iTeach);
});

test('a shared spoken language with no exchange is mildly positive', () => {
  const score = ranking.languageScore(who(['en'], []), who(['en'], []));
  assert.equal(score, 0.55);
});

test('no exchange and no shared language is demoted, never excluded', () => {
  // Translation still makes the conversation possible, so this is the
  // weakest pairing rather than a disqualification. Zero would be filtering
  // by the back door, which the spec rules out.
  const score = ranking.languageScore(who(['en'], []), who(['ja'], []));
  assert.equal(score, 0.35);
  assert.ok(score > 0);
});

test('undeclared scores NEUTRAL, above a declared-but-poor match', () => {
  // Every account predates this feature, including the App Review demo
  // account. An unknown must never rank below a known-bad pairing.
  const unknown = ranking.languageScore(who(['en'], []), who([], []));
  const declaredPoor = ranking.languageScore(who(['en'], []), who(['ja'], []));

  assert.equal(unknown, 0.5);
  assert.ok(unknown > declaredPoor);
});

test('either side undeclared is neutral', () => {
  assert.equal(ranking.languageScore(who([], []), who(['ko'], ['en'])), 0.5);
  assert.equal(ranking.languageScore(undefined, who(['ko'], [])), 0.5);
  assert.equal(ranking.languageScore(who(['ko'], []), undefined), 0.5);
});

test('codes compare case-insensitively', () => {
  assert.equal(ranking.languageScore(who(['EN'], ['KO']), who(['ko'], ['en'])), 1.0);
});

test('the weights still sum to one', () => {
  const sum = Object.values(ranking.WEIGHTS).reduce((a, b) => a + b, 0);
  assert.ok(Math.abs(sum - 1) < 1e-9, `weights sum to ${sum}`);
});

test('language matters, but less than interests', () => {
  // The premise should shape the deck, not dictate it: someone with nothing
  // in common but a convenient language pair is not a better match than
  // someone who shares your life.
  assert.equal(ranking.WEIGHTS.language, 0.20);
  assert.ok(ranking.WEIGHTS.language < ranking.WEIGHTS.interests);
});

test('scoreCandidate reports language in its breakdown', () => {
  const { components } = ranking.scoreCandidate(
    { _id: 'v', ...who(['en'], ['ko']) },
    { _id: 'c', lastActive: new Date(), ...who(['ko'], ['en']) },
    { now: new Date() },
  );

  assert.ok('language' in components, 'a score you cannot explain cannot be tuned');
  assert.equal(components.language, 1.0);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/firdavsmutalipov/Projects/BananaTalk/backend && node --test flame/__tests__/languageRanking.test.js`
Expected: FAIL — `ranking.languageScore is not a function`.

- [ ] **Step 3: Rebalance the weights**

In `flame/services/rankingService.js`, replace the `WEIGHTS` object:

```javascript
const WEIGHTS = Object.freeze({
  interests: 0.22,
  distance: 0.20,
  language: 0.20,
  activity: 0.18,
  reciprocity: 0.12,
  completeness: 0.08,
});
```

Update the doc comment above it to add:

```
 * - **Language fourth in weight but first in intent.** It is what makes this
 *   app the thing it is, and it is still below `interests`: the premise should
 *   shape the deck, not dictate it. Someone with nothing in common but a
 *   convenient language pair is not a better match than someone who shares
 *   your life.
```

- [ ] **Step 4: Add languageScore**

In `flame/services/rankingService.js`, above `scoreCandidate`:

```javascript
/**
 * Complementarity between two people's languages — NOT sameness.
 *
 * The pairing this app exists for is an exchange: I speak English and am
 * learning Korean, you speak Korean and are learning English. Scoring simple
 * overlap would reward two English speakers and miss the point entirely.
 *
 * The asymmetry between the two one-directional cases is deliberate. The deck
 * is ordered FOR THE VIEWER, so someone who can teach the viewer what they are
 * learning is worth more than someone who merely wants what the viewer already
 * has.
 *
 * Nothing here returns 0. No shared language at all is the weakest pairing, but
 * chat translation still makes the conversation possible — and a zero would be
 * filtering by the back door, which the design explicitly rules out in favour
 * of ranking.
 */
function languageScore(viewer, candidate) {
  const list = (x) => (Array.isArray(x) ? x.filter(Boolean).map((c) => String(c).toLowerCase()) : []);

  const mySpoken = list(viewer && viewer.languagesSpoken);
  const myLearning = list(viewer && viewer.languagesLearning);
  const theirSpoken = list(candidate && candidate.languagesSpoken);
  const theirLearning = list(candidate && candidate.languagesLearning);

  // Undeclared on either side is UNKNOWN, and unknown is never bad. Every
  // account predates this feature; burying them for a field that did not
  // exist when they signed up would be wrong.
  if (mySpoken.length === 0 || theirSpoken.length === 0) return NEUTRAL;

  const overlaps = (a, b) => a.some((x) => b.includes(x));

  const theyTeachMe = overlaps(theirSpoken, myLearning);
  const iTeachThem = overlaps(mySpoken, theirLearning);

  if (theyTeachMe && iTeachThem) return 1.0;
  if (theyTeachMe) return 0.85;
  if (iTeachThem) return 0.75;
  if (overlaps(mySpoken, theirSpoken)) return 0.55;
  return 0.35;
}
```

- [ ] **Step 5: Wire it into scoreCandidate and the exports**

In `scoreCandidate`'s `components` object, add:

```javascript
    language: languageScore(viewer, candidate),
```

In `module.exports`, add `languageScore,`.

- [ ] **Step 6: Run test to verify it passes**

Run: `cd /Users/firdavsmutalipov/Projects/BananaTalk/backend && node --test flame/__tests__/languageRanking.test.js`
Expected: PASS, 10 tests.

- [ ] **Step 7: Run the ranking and discovery regression**

Run:
```bash
node --test flame/__tests__/ranking.test.js flame/__tests__/languageRanking.test.js \
  flame/__tests__/discoverFilters.test.js flame/__tests__/discoverDistance.test.js \
  flame/__tests__/distancePrivacy.test.js
```
Expected: all PASS. `ranking.test.js` has a weights-sum assertion that must still hold.

- [ ] **Step 8: Verify blast radius and commit**

```bash
git status --short | awk '{print $2}' | grep -v '^flame/'   # must print nothing
git add flame/services/rankingService.js flame/__tests__/languageRanking.test.js
git commit -m "feat(flame): rank on language complementarity

Scores an exchange, not an overlap: I speak English and am learning Korean,
you speak Korean and are learning English. Simple overlap would reward two
English speakers and miss the entire point.

They-teach-me (0.85) outranks I-teach-them (0.75) because the deck is
ordered for the viewer. Nothing scores 0 — no shared language is the
weakest pairing, not a disqualification, since translation still makes the
conversation possible and a zero would be filtering by the back door.

Undeclared scores 0.50, ABOVE a declared-but-poor 0.35: every account
predates this field and must not be buried for it.

Weights rebalanced to keep the sum at 1. Language sits below interests
deliberately — the premise should shape the deck, not dictate it."
```

---

### Task 6: The language picker, and its two rows in registration

**Files:**
- Create: `lib/screens/languages/language_picker_screen.dart`
- Create: `lib/core/languages/language_label.dart`
- Modify: `lib/screens/auth/registration/steps/step_bio_interests.dart`
- Modify: `lib/screens/auth/registration/registration_flow.dart` (`RegistrationData`)
- Modify: `lib/services/auth_service.dart`, `lib/providers/auth_provider.dart` (register body)
- Modify: `lib/l10n/app_en.arb` **and all 25 base locale ARBs** (4 new keys)
- Test: `test/screens/languages/language_picker_test.dart`

**Interfaces:**
- Consumes: `Language`, `kLanguageFallback`, `kRecommendedCodes` (Task 1); `languageCatalogProvider` (Task 2).
- Produces: `LanguagePickerScreen`, `languageLabel(String code, List<Language> catalog)`, `RegistrationData.languagesSpoken` / `.languagesLearning`.

**A picker screen, not a chip grid.** 127+ languages will not fit as chips, and
one tappable row reading "English, 한국어" adds far less to the rejected
registration screen than a wall of forty chips would. Mirrors
`bananatalk_app/lib/widgets/language_selection/language_picker_screen.dart`:
search, a Recommended section, then alphabetical.

- [ ] **Step 1: Add four l10n keys to English, then all 25 base locales**

Keys: `languagesSpokenLabel` → `"Languages you speak"`,
`languagesLearningLabel` → `"Languages you're learning"`,
`languagesPickerTitle` → `"Select languages"`,
`languagesNoneSelected` → `"None selected"`.

`arb_parity_test` fails unless every key exists in all 25 base ARBs with a real
translation — English placeholders are not acceptable, matching how the
notification and location strings were handled.

Then: `flutter gen-l10n && flutter test test/l10n/` → PASS.

- [ ] **Step 2: Write the failing test**

```dart
// test/screens/languages/language_picker_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/languages/language.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/providers/languages_provider.dart';
import 'package:flame/screens/languages/language_picker_screen.dart';

final _catalog = [
  const Language(code: 'en', name: 'English', nativeName: 'English'),
  const Language(code: 'ko', name: 'Korean', nativeName: '한국어'),
  const Language(code: 'zu', name: 'Zulu', nativeName: 'isiZulu'),
];

Widget _host({
  required List<String> initial,
  required ValueChanged<List<String>> onDone,
  int max = 3,
}) =>
    ProviderScope(
      overrides: [
        languageCatalogProvider.overrideWith((ref) async => _catalog),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LanguagePickerScreen(
          initialSelection: initial,
          maxSelection: max,
          onDone: onDone,
        ),
      ),
    );

void main() {
  testWidgets('lists languages under their own names', (tester) async {
    await tester.pumpWidget(_host(initial: const [], onDone: (_) {}));
    await tester.pumpAndSettle();

    expect(find.text('한국어'), findsOneWidget);
    expect(find.text('isiZulu'), findsOneWidget);
  });

  testWidgets('search matches the ENGLISH name too', (tester) async {
    // Someone whose keyboard is English must be able to find 한국어 by
    // typing "Korean" — that is what Language.name is carried for.
    await tester.pumpWidget(_host(initial: const [], onDone: (_) {}));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'korean');
    await tester.pumpAndSettle();

    expect(find.text('한국어'), findsOneWidget);
    expect(find.text('isiZulu'), findsNothing);
  });

  testWidgets('search matches the native name as well', (tester) async {
    await tester.pumpWidget(_host(initial: const [], onDone: (_) {}));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '한국');
    await tester.pumpAndSettle();

    expect(find.text('한국어'), findsOneWidget);
  });

  testWidgets('selecting returns the codes, not the labels', (tester) async {
    List<String>? got;
    await tester.pumpWidget(_host(initial: const [], onDone: (v) => got = v));
    await tester.pumpAndSettle();

    await tester.tap(find.text('한국어'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language_picker_done')));
    await tester.pumpAndSettle();

    expect(got, ['ko']);
  });

  testWidgets('the cap is enforced and the extra tap does not stick',
      (tester) async {
    List<String>? got;
    await tester.pumpWidget(_host(
      initial: const ['en', 'ko'], onDone: (v) => got = v, max: 2,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('isiZulu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language_picker_done')));
    await tester.pumpAndSettle();

    expect(got, ['en', 'ko']);
  });

  testWidgets('an already-selected language can be deselected', (tester) async {
    List<String>? got;
    await tester.pumpWidget(_host(initial: const ['ko'], onDone: (v) => got = v));
    await tester.pumpAndSettle();

    await tester.tap(find.text('한국어'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language_picker_done')));
    await tester.pumpAndSettle();

    expect(got, isEmpty);
  });

  testWidgets('a failed catalogue still shows the bundled fallback',
      (tester) async {
    // The picker is on the registration screen. Empty is not an option.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        languageCatalogProvider.overrideWith((ref) async => kLanguageFallback),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LanguagePickerScreen(
          initialSelection: const [], maxSelection: 3, onDone: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('English'), findsWidgets);
  });
}
```

Add `import 'package:flame/core/languages/language_fallback.dart';` for the last test.

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/screens/languages/language_picker_test.dart`
Expected: FAIL — `language_picker_screen.dart` does not exist.

- [ ] **Step 4: Write the label helper**

```dart
// lib/core/languages/language_label.dart
import 'package:flame/core/languages/language.dart';
import 'package:flame/core/languages/language_fallback.dart';

/// The display name for [code], given whatever catalogue is loaded.
///
/// Falls through the loaded catalogue, then the bundled fallback, then the
/// raw code — mirroring BananaTalk's getLanguageName, which degrades to the
/// code rather than throwing. A code can arrive from a newer client or survive
/// a catalogue edit, and rendering "zz" on a profile is a blemish where
/// crashing the profile is a bug.
String languageLabel(String code, List<Language> catalog) {
  final lower = code.toLowerCase();
  for (final l in catalog) {
    if (l.code == lower) return l.nativeName;
  }
  for (final l in kLanguageFallback) {
    if (l.code == lower) return l.nativeName;
  }
  return code;
}
```

- [ ] **Step 5: Write the picker**

Mirror `bananatalk_app/lib/widgets/language_selection/language_picker_screen.dart`:

- `ConsumerStatefulWidget` taking `initialSelection`, `maxSelection`, `onDone`.
- Watches `languageCatalogProvider`; `AsyncValue.when` renders a spinner while
  loading and **`kLanguageFallback` on error** — never an empty list.
- A `TextField` filtering on `name` OR `nativeName`, both lowercased, so
  "korean" and "한국" both work.
- A **Recommended** section above the alphabetical list, from
  `kRecommendedCodes`, hidden once a search is typed (their behaviour).
- Each row: `Text('${lang.flag}  ${lang.nativeName}')` with the English name as
  a subtitle when it differs, and a check when selected.
- Tapping toggles; adding beyond `maxSelection` is ignored, and the app bar
  shows `selected.length / maxSelection` so the cap is visible before it bites.
- A **Done** button keyed `language_picker_done` calling `onDone(selectedCodes)`.

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/screens/languages/language_picker_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 7: Add the two rows to registration step 4**

In `registration_flow.dart`, add to `RegistrationData`:

```dart
  /// ISO 639-1 codes, max 3 each. Spoken is seeded from the device locale the
  /// first time step 4 builds.
  List<String> languagesSpoken = [];
  List<String> languagesLearning = [];
```

In `step_bio_interests.dart`, below the interests grid, add two rows built by:

```dart
  Widget _languageRow({
    required String label,
    required List<String> codes,
    required Key key,
    required void Function(List<String>) onChanged,
  }) {
    final catalog = ref.watch(languageCatalogProvider).valueOrNull
        ?? kLanguageFallback;
    final summary = codes.isEmpty
        ? context.l10n.languagesNoneSelected
        : codes.map((c) => languageLabel(c, catalog)).join(', ');

    return ListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(summary),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LanguagePickerScreen(
          initialSelection: codes,
          maxSelection: 3,
          onDone: (picked) => setState(() => onChanged(picked)),
        ),
      )),
    );
  }
```

Note this makes the step a `ConsumerStatefulWidget` if it is not already.

And seed the spoken list once, at the top of `build`:

```dart
  /// Pre-selects the device's language, once.
  ///
  /// A Korean phone opens this step with 한국어 already chosen. That populates
  /// the app's premise for essentially every new user at zero friction — and
  /// deliberately without adding a second blocking requirement to the step
  /// whose first one produced the "Skip for now was unresponsive" rejection.
  void _seedFromLocale(BuildContext context) {
    if (_seededLanguages) return;
    _seededLanguages = true;
    if (widget.data.languagesSpoken.isNotEmpty) return;

    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    final catalog = ref.read(languageCatalogProvider).valueOrNull
        ?? kLanguageFallback;
    if (catalog.any((l) => l.code == code)) {
      widget.data.languagesSpoken = [code];
    }
  }
```

- [ ] **Step 8: Send them on register**

In `auth_service.dart`'s `register`, add two optional `List<String>` named
parameters and include them in the body as `languagesSpoken` /
`languagesLearning`. Mirror on `AuthNotifier.register`, and pass
`_data.languagesSpoken` / `_data.languagesLearning` from the flow's submit.

- [ ] **Step 9: Full suite, analyze, commit**

```bash
flutter test 2>&1 | tail -3
flutter analyze 2>&1 | grep -c "error •"   # 0

git add lib/screens/languages lib/core/languages/language_label.dart \
        lib/screens/auth/registration lib/services/auth_service.dart \
        lib/providers/auth_provider.dart lib/l10n \
        test/screens/languages/language_picker_test.dart
git commit -m "feat(register): declare your languages, seeded from the device

A picker SCREEN, not a chip grid: 127 languages will not fit as chips, and
one row reading 'English, 한국어' adds far less to the registration screen
App Review rejected than a wall of forty chips would. Mirrors BananaTalk's
picker -- search, Recommended, alphabetical.

Search matches the English name as well as the native one, so someone on an
English keyboard can find 한국어 by typing Korean.

Spoken languages pre-select from the device locale, so a Korean phone opens
with 한국어 already chosen: the premise is populated for essentially every
new user at zero friction, and without adding a second blocking gate to the
step whose first one produced the 'Skip for now was unresponsive'
rejection."
```

---

### Task 7: Visibility — card, profile, chat

**Files:**
- Modify: `lib/widgets/profile_card.dart` (deck card line)
- Modify: `lib/screens/profile/my_profile_screen.dart` and `lib/screens/profile/profile_detail_screen.dart` (languages row)
- Modify: `lib/screens/chat/widgets/message_bubble.dart` (translation default)
- Create: `lib/widgets/languages_line.dart`
- Modify: `lib/l10n/app_en.arb` + 25 locales (2 new keys)
- Test: `test/widgets/languages_line_test.dart` (create)

**Interfaces:**
- Consumes: `User.languagesSpoken` / `languagesLearning` (Task 4), `languageLabel(code, catalog)` (Task 6), `languageCatalogProvider` (Task 2).
- Produces: `LanguagesLine` widget.

**This is the task that actually answers Guideline 4.3(b).** Ranking is invisible; a reviewer with a fresh account may see no reordering at all. These three surfaces are what make the premise legible in thirty seconds.

- [ ] **Step 1: Add the two l10n keys to English and all 25 locales**

Keys: `profileSpeaks` → `"Speaks"`, `profileLearning` → `"Learning"`.
Same procedure and translation requirement as Task 6 Steps 1–2.
Then `flutter gen-l10n` and `flutter test test/l10n/` → PASS.

- [ ] **Step 2: Write the failing test**

```dart
// test/widgets/languages_line_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/languages/language.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/providers/languages_provider.dart';
import 'package:flame/widgets/languages_line.dart';

/// LanguagesLine is a ConsumerWidget reading the catalogue, so it needs a
/// ProviderScope. The catalogue is overridden rather than fetched — these
/// tests are about the line, not the network.
Widget _host(Widget child) => ProviderScope(
      overrides: [
        languageCatalogProvider.overrideWith((ref) async => const [
              Language(code: 'ko', name: 'Korean', nativeName: '한국어'),
              Language(code: 'en', name: 'English', nativeName: 'English'),
              Language(code: 'ja', name: 'Japanese', nativeName: '日本語'),
            ]),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('shows spoken and learning languages by their own names',
      (tester) async {
    await tester.pumpWidget(_host(const LanguagesLine(
      spoken: ['ko'],
      learning: ['en'],
    )));

    expect(find.textContaining('한국어'), findsOneWidget);
    expect(find.textContaining('English'), findsOneWidget);
  });

  testWidgets('renders nothing at all when nothing is declared',
      (tester) async {
    // Every existing account. An empty row with a dangling label reads as
    // broken data.
    await tester.pumpWidget(_host(const LanguagesLine(
      spoken: [],
      learning: [],
    )));

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('omits the learning half when only spoken is declared',
      (tester) async {
    await tester.pumpWidget(_host(const LanguagesLine(
      spoken: ['ja'],
      learning: [],
    )));

    expect(find.textContaining('日本語'), findsOneWidget);
    expect(find.textContaining('Learning'), findsNothing);
  });

  testWidgets('an unknown code degrades to the code rather than crashing',
      (tester) async {
    await tester.pumpWidget(_host(const LanguagesLine(
      spoken: ['zz'],
      learning: [],
    )));

    expect(find.textContaining('zz'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/widgets/languages_line_test.dart`
Expected: FAIL — `languages_line.dart` does not exist.

- [ ] **Step 4: Write the widget**

```dart
// lib/widgets/languages_line.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/languages/language_fallback.dart';
import 'package:flame/core/languages/language_label.dart';
import 'package:flame/providers/languages_provider.dart';

/// "Speaks 한국어 · Learning English".
///
/// The premise, made visible. Ranking cannot be seen — in a sparse pool it may
/// not even be felt — so this line is what tells someone, and an App Store
/// reviewer, what this app is for within seconds of opening it.
///
/// Renders NOTHING when nothing is declared. Every account created before this
/// feature has empty lists, and a label with no value after it reads as broken
/// data rather than as an absent answer.
class LanguagesLine extends ConsumerWidget {
  const LanguagesLine({
    super.key,
    required this.spoken,
    required this.learning,
    this.style,
  });

  final List<String> spoken;
  final List<String> learning;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // valueOrNull with a fallback rather than AsyncValue.when: this line sits
    // on a deck card, and a spinner where a language should be is worse than
    // a name resolved from the bundled list.
    final catalog =
        ref.watch(languageCatalogProvider).valueOrNull ?? kLanguageFallback;
    String label(String c) => languageLabel(c, catalog);

    final parts = <String>[];

    if (spoken.isNotEmpty) {
      parts.add('${context.l10n.profileSpeaks} ${spoken.map(label).join(', ')}');
    }
    if (learning.isNotEmpty) {
      parts.add('${context.l10n.profileLearning} '
          '${learning.map(label).join(', ')}');
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' · '),
      key: const Key('languages_line'),
      style: style,
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/widgets/languages_line_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 6: Place it on the three surfaces**

- `lib/widgets/profile_card.dart` — under the name/age row, beside the distance label, using the card's existing secondary text style.
- `lib/screens/profile/my_profile_screen.dart` — under the location row added on 2026-09-02.
- `lib/screens/profile/profile_detail_screen.dart` — in the details block, near interests.

- [ ] **Step 7: Default chat translation on when languages differ**

In `lib/screens/chat/widgets/message_bubble.dart`, where translation is currently
opt-in, default it to on when the viewer's `languagesSpoken` and the partner's
share no entry. Guard on both lists being non-empty — unknown must not force
translation on, only a known mismatch may.

- [ ] **Step 8: Full app suite, analyze, and both builds**

Run:
```bash
flutter test 2>&1 | tail -3
flutter analyze 2>&1 | grep -c "error •"
flutter build apk --debug 2>&1 | tail -2
flutter build ios --no-codesign --debug 2>&1 | tail -2
```
Expected: all tests pass; `0`; both builds succeed.

- [ ] **Step 9: Commit**

```bash
git add lib/widgets/languages_line.dart lib/widgets/profile_card.dart \
        lib/screens/profile lib/screens/chat/widgets/message_bubble.dart \
        lib/l10n test/widgets/languages_line_test.dart
git commit -m "feat(languages): show the premise, because ranking cannot be seen

Guideline 4.3(b) is answered in the first thirty seconds or not at all, and
a ranking component is invisible — in a sparse pool it may not even be felt.
The card line, the profile row and translation defaulting on for a genuine
language mismatch are what make the app legible as what it is.

Renders nothing when nothing is declared: every existing account has empty
lists, and a label with no value reads as broken data rather than as an
absent answer."
```

---

### Task 8: Demo account and App Store metadata

**Files:**
- Create: `docs/app-store/2026-09-resubmission-metadata.md`

**Interfaces:**
- Consumes: everything above.
- Produces: copy for App Store Connect, and a configured review account.

**Neither half is code, and both decide whether the work is seen.** The reviewer signs in with the demo account; if it renders none of Task 7, the differentiation does not exist as far as the rejection is concerned.

- [ ] **Step 1: Give the demo account languages and photos**

Against production, signed in as `appreview1@banatalk.com`:

```bash
# languages — makes Task 7 render for the reviewer
curl -s -X PATCH https://api.banatalk.com/flamebackend/v1/users/me \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"languagesSpoken":["en"],"languagesLearning":["ko","es"]}'
```

Photos must be uploaded through the app — the account currently has `photos: []`,
and an empty dating profile is not "full access to the app's features and
functionality", which is the guideline already cited.

Verify:

```bash
curl -s -X POST https://api.banatalk.com/flamebackend/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"appreview1@banatalk.com","password":"$FLAME_REVIEW_PW"}' \
  | python3 -m json.tool | grep -E 'languages|photos'
```
Expected: non-empty `languagesSpoken`, `languagesLearning`, and `photos`.

- [ ] **Step 2: Seed two complementary accounts**

Create two accounts whose languages complement the demo account's — one
speaking Korean and learning English, one speaking Spanish and learning
English — within the demo account's distance radius, each with photos and a
bio. Without them the reviewer's deck shows the feature working on nobody.

- [ ] **Step 3: Write the metadata document**

Create `docs/app-store/2026-09-resubmission-metadata.md` containing:

- **App name** (30 char limit) — leads with the premise, not the category. `Flame Dating App: Meet & Date` must go; it is the strongest evidence for the rejection received.
- **Subtitle** (30 chars) — states the difference.
- **Description** — first two lines state what is different before anything else; the cross-language premise, then translation, then the usual feature list.
- **Screenshot captions** — first two show a language-complementary card and a translated conversation. Not a swipe deck.
- **Review notes** — demo credentials, and one paragraph telling the reviewer what to look at: the languages on the card, and the translated chat.
- **The face-data answers** for the separate Guideline 2.1 request, quoting privacy policy section 5 verbatim: *"We do not run face recognition, we do not compute a faceprint or any biometric identifier, we do not compare your face against any database, and photos are not sent anywhere for this purpose."*

- [ ] **Step 4: Bump the build number**

`pubspec.yaml` and `lib/config/app_version.dart` must agree —
`test/config/app_version_test.dart` fails the build otherwise. The reviewed
build was `10001`; the current value is `10002`.

Run: `flutter test test/config/app_version_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add docs/app-store/2026-09-resubmission-metadata.md pubspec.yaml lib/config/app_version.dart
git commit -m "docs(app-store): resubmission metadata and review notes

The name and first two screenshots carry more of the 4.3(b) answer than
their size suggests: 'Flame Dating App: Meet & Date' is the most generic
submission possible and reads as evidence for the rejection it received.

Also records the demo-account setup, because the reviewer sees the premise
only through that account — with no languages and no photos it renders
none of this."
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| §1 Data model — app | 1, 4 |
| §1 Data model — backend | 2, 3 |
| §1 Catalogue | 1 (model, flags, fallback), 2 (endpoint + fetch ladder) |
| §2 Onboarding, device-locale seed | 6 |
| §3 Ranking, rebalanced weights | 5 |
| §3 Unknown = neutral | 3, 5 (tested in both) |
| §4 Deck card / chat / profile | 7 |
| §4 Demo account | 8 |
| §5 Metadata | 8 |
| §6 Testing | every task |

No gaps.

**Placeholder scan:** No TBD/TODO. Every code step carries real code. The two
steps that describe placement rather than quoting code (Task 7 Step 6, Task 6
Step 6) name exact files and the exact existing widget structure to mirror.

**Type consistency:** `languagesSpoken` / `languagesLearning` are the field names
in Dart, Mongoose, and both wire directions except the discovery response, which
is `languages_spoken` / `languages_learning` to match `User.fromJson`'s existing
snake_case convention (Task 3 Step 6 defines it, Task 4 Step 3 parses it).
`Language.fromJson` and `LanguageFlags.getFlag` are defined in Task 1;
`parseLanguageCatalog` / `resolveCatalog` / `languageCatalogProvider` in Task 2;
`languageLabel(String, List<Language>)` in Task 6 and used by Task 7 under that
exact name. There is no synchronous global name lookup — the catalogue is
fetched, so every consumer takes the loaded list and falls back to
`kLanguageFallback`. `languageScore(viewer, candidate)` is
defined in Task 5 and referenced nowhere earlier.

**One risk worth restating:** Task 7 is what answers the rejection. If the plan is
executed partially, executing 1–6 and skipping 7 produces a correct feature that
no reviewer will notice.
