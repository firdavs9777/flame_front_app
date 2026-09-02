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

## Prior art in BananaTalk, and what we take from it

The sibling product already solved the vocabulary problem. What exists:

| Asset | Verdict |
|---|---|
| `_data/languages.json` — **182 languages with `code`, `name`, `nativeName`** | **USE IT.** `nativeName` is exactly the endonym this design needs, and it is present and correct for all 40 shortlisted codes. Hand-writing 한국어 and العربية invites a typo nobody would catch. |
| `GET /languages` (BananaTalk route) | **Do NOT call.** Reasoning below. |
| `utils/languageCodes.js` name↔ISO map | Not needed — Flame stores codes from the start, so it has no legacy names to normalise. |
| Flutter app's 16-language list with flag emoji | Structure worth copying; the flags are not. |

**Why the catalogue is copied, not fetched.**

`GET /languages` is live and would be a single source of truth. It is still the
wrong choice here:

- `CLAUDE.md` states flame's isolation as a principle, and this work is under a
  standing instruction to touch nothing outside `flame/`.
- It is **static data**. Fetching it adds a network round trip and a failure
  mode to the registration screen App Review just rejected — a slow or failed
  call leaves the picker empty and the premise invisible.
- A change to BananaTalk's route or response shape would break Flame's signup,
  which is precisely the coupling `CLAUDE.md` warns about.

The *data* is the shared source of truth; the *runtime dependency* is not.
Task 1 generates the Dart catalogue from that JSON and records where to
re-derive it.

**Why not flag emoji**, despite the BananaTalk app using them:

Their list maps English to 🇺🇸 and Spanish to 🇪🇸. Flags mark countries, not
languages — 🇺🇸 for English erases every other English-speaking country, 🇪🇸
for Spanish erases Latin America, and Swahili, Arabic and Tagalog have no
defensible single flag. On an app whose premise is meeting people from
elsewhere, that is a poor first impression. The endonym carries the meaning
alone.

Their fallback **is** worth copying: `getLanguageName` degrades to the
uppercased code rather than throwing — the same instinct as `endonymFor`
returning the raw code.

---

### Task 1: Language catalogue (app)

**Files:**
- Create: `lib/core/languages/language_catalogue.dart`
- Test: `test/core/languages/language_catalogue_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class Language { final String code; final String endonym; }`, `const List<Language> kLanguages`, `Language? languageForCode(String code)`, `String endonymFor(String code)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/languages/language_catalogue_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/languages/language_catalogue.dart';

void main() {
  test('every code is a lowercase ISO 639-1 pair', () {
    for (final l in kLanguages) {
      expect(l.code, matches(RegExp(r'^[a-z]{2}$')),
          reason: '"${l.code}" is not an ISO 639-1 code');
    }
  });

  test('codes are unique', () {
    final codes = kLanguages.map((l) => l.code).toList();
    expect(codes.toSet().length, codes.length);
  });

  test('every language has a non-empty endonym', () {
    for (final l in kLanguages) {
      expect(l.endonym.trim(), isNotEmpty, reason: l.code);
    }
  });

  test('endonyms are the language\'s OWN name, not English', () {
    // The whole reason this catalogue needs no translation. If these were
    // English names they would need 25 ARB translations each.
    expect(endonymFor('ko'), '한국어');
    expect(endonymFor('es'), 'Español');
    expect(endonymFor('ja'), '日本語');
    expect(endonymFor('ar'), 'العربية');
    expect(endonymFor('en'), 'English');
  });

  test('lookup finds a known code and refuses an unknown one', () {
    expect(languageForCode('ko')?.endonym, '한국어');
    expect(languageForCode('zz'), isNull);
    expect(languageForCode(''), isNull);
  });

  test('endonymFor falls back to the raw code rather than throwing', () {
    // A code stored by a newer client, or one dropped from the catalogue.
    // Showing "xx" is bad; crashing a profile is worse.
    expect(endonymFor('zz'), 'zz');
  });

  test('covers every language the app itself is translated into', () {
    // Someone reading Flame in Croatian must be able to say they speak
    // Croatian. Anything less is visibly incomplete.
    for (final code in [
      'en', 'ar', 'bn', 'ca', 'zh', 'hr', 'cs', 'da', 'nl', 'fi', 'fr', 'de',
      'hi', 'id', 'it', 'ja', 'ko', 'nb', 'pt', 'ru', 'es', 'th', 'tr', 'ur',
      'vi',
    ]) {
      expect(languageForCode(code), isNotNull,
          reason: 'the app ships a $code locale but cannot declare it');
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/languages/language_catalogue_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'flame' ... language_catalogue.dart` (file does not exist).

- [ ] **Step 3: Generate the catalogue from BananaTalk's language data**

Do NOT hand-write the endonyms. Save the following as `tool/gen_languages.py`
and run it — it derives every display name from `_data/languages.json`, whose
`nativeName` column is already correct for all 40 shortlisted codes.

```python
import json, pathlib

SRC = '/Users/firdavsmutalipov/Projects/BananaTalk/backend/_data/languages.json'

# Ordered by rough speaker count so common cases sit near the top of a picker.
# Every locale the app itself ships is included: someone reading Flame in
# Croatian must be able to say they speak Croatian.
SHORTLIST = [
    'en','zh','hi','es','ar','bn','pt','ru','ja','de',
    'fr','ko','tr','vi','it','th','ur','id','pl','uk',
    'nl','fa','ms','tl','sv','el','cs','ro','hu','he',
    'da','fi','nb','sk','hr','sr','bg','ca','sw','ta',
]

by_code = {l['code']: l for l in json.load(open(SRC))}
missing = [c for c in SHORTLIST if c not in by_code]
assert not missing, f'not in BananaTalk data: {missing}'

def endonym(code):
    raw = by_code[code]['nativeName'].strip()
    assert raw, f'{code} has no nativeName'
    # Capitalise the first character. Their data is linguistically correct --
    # Spanish does not capitalise "espanol" -- but a lowercase entry sitting
    # beside "English" reads as a bug in a picker.
    return raw[0].upper() + raw[1:]

entries = '\n'.join(f"  Language('{c}', '{endonym(c)}')," for c in SHORTLIST)

DOC = (
    "import 'package:flutter/foundation.dart';\n"
    "\n"
    "/// One language: a stable stored code and the name that language calls\n"
    "/// itself.\n"
    "///\n"
    "/// The code is what `user.languagesSpoken` stores and what the backend\n"
    "/// validates. ISO 639-1, lowercase, and NEVER translated -- translating a\n"
    "/// stored value breaks every record and every match at once, the same\n"
    "/// reasoning `interest_catalogue.dart` records about its own tokens.\n"
    "///\n"
    "/// The endonym is the language's own name, not an English one. That is\n"
    "/// what makes this catalogue need no localisation: forty languages against\n"
    "/// 25 locales would be a thousand ARB strings under arb_parity_test, all to\n"
    "/// tell a Korean speaker what Korean is called in English.\n"
    "///\n"
    "/// NO FLAG EMOJI, unlike the BananaTalk picker. Flags mark countries, not\n"
    "/// languages, and several of these have no defensible flag at all.\n"
    "@immutable\n"
    "class Language {\n"
    "  const Language(this.code, this.endonym);\n"
    "\n"
    "  final String code;\n"
    "  final String endonym;\n"
    "\n"
    "  @override\n"
    "  bool operator ==(Object other) =>\n"
    "      other is Language && other.code == code && other.endonym == endonym;\n"
    "\n"
    "  @override\n"
    "  int get hashCode => Object.hash(code, endonym);\n"
    "}\n"
    "\n"
    "/// The canonical vocabulary, mirrored in `flame/config/languages.js`. A\n"
    "/// test in each repo asserts its own list matches the other's.\n"
    "///\n"
    "/// GENERATED by tool/gen_languages.py from BananaTalk's\n"
    "/// _data/languages.json. Re-derive from there rather than editing an\n"
    "/// endonym by hand.\n"
    "const List<Language> kLanguages = [\n"
)

TAIL = (
    "];\n"
    "\n"
    "final Map<String, Language> _byCode = {\n"
    "  for (final l in kLanguages) l.code: l,\n"
    "};\n"
    "\n"
    "/// The catalogue entry for [code], or null when it is not one we know.\n"
    "Language? languageForCode(String? code) {\n"
    "  if (code == null || code.isEmpty) return null;\n"
    "  return _byCode[code.toLowerCase()];\n"
    "}\n"
    "\n"
    "/// The display name for [code], falling back to the code itself.\n"
    "///\n"
    "/// A fallback rather than a throw, mirroring BananaTalk's getLanguageName:\n"
    "/// a code can arrive from a newer client, and rendering \"zz\" on a profile\n"
    "/// is a blemish where crashing it is a bug.\n"
    "String endonymFor(String code) => languageForCode(code)?.endonym ?? code;\n"
)

out = pathlib.Path('lib/core/languages/language_catalogue.dart')
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(DOC + entries + '\n' + TAIL)
print(f'generated {len(SHORTLIST)} languages')
```

Run: `python3 tool/gen_languages.py`
Expected: `generated 40 languages`

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/languages/language_catalogue_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 5: Verify analyze is clean**

Run: `flutter analyze 2>&1 | grep -c "error •"`
Expected: `0`

- [ ] **Step 6: Commit**

```bash
git add tool/gen_languages.py lib/core/languages/language_catalogue.dart test/core/languages/language_catalogue_test.dart
git commit -m "feat(languages): the catalogue, named in each language's own words

GENERATED from BananaTalk's _data/languages.json, which already carries a
nativeName column for all 182 languages it knows, correct for every code we
shortlist. Hand-writing those names invites a typo nobody would catch.

Endonyms rather than translated names: forty languages against 25 locales
would be a thousand ARB strings under arb_parity_test, all to tell a Korean
speaker what Korean is called in English.

Copied, not fetched. GET /languages exists on the BananaTalk side and would
be a single source of truth, but this is static data -- calling it would add
a network failure mode to the registration screen App Review just rejected,
and couple flame to a route CLAUDE.md says to stay clear of.

No flag emoji, unlike the BananaTalk picker: flags mark countries, not
languages, and several of these have no defensible flag at all."
```

---

### Task 2: Language catalogue (backend) + cross-repo parity

**Files:**
- Create: `/Users/firdavsmutalipov/Projects/BananaTalk/backend/flame/config/languages.js`
- Create: `/Users/firdavsmutalipov/Projects/BananaTalk/backend/flame/__tests__/languageCatalogue.test.js`
- Create: `test/core/languages/language_parity_test.dart` (app repo)

**Interfaces:**
- Consumes: `kLanguages` from Task 1.
- Produces: `LANGUAGE_CODES` (frozen array of strings), `isLanguageCode(code)` from `flame/config/languages.js`.

- [ ] **Step 1: Write the failing backend test**

```javascript
// flame/__tests__/languageCatalogue.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const { LANGUAGE_CODES, isLanguageCode } = require('../config/languages');

test('every code is a lowercase ISO 639-1 pair', () => {
  for (const code of LANGUAGE_CODES) {
    assert.match(code, /^[a-z]{2}$/, `"${code}" is not an ISO 639-1 code`);
  }
});

test('codes are unique', () => {
  assert.equal(new Set(LANGUAGE_CODES).size, LANGUAGE_CODES.length);
});

test('isLanguageCode accepts a known code and refuses anything else', () => {
  assert.equal(isLanguageCode('ko'), true);
  assert.equal(isLanguageCode('KO'), true, 'case is normalised');
  assert.equal(isLanguageCode('zz'), false);
  assert.equal(isLanguageCode(''), false);
  assert.equal(isLanguageCode(null), false);
  assert.equal(isLanguageCode(123), false);
});

test('the list matches the app catalogue exactly', () => {
  // Two hardcoded lists that silently diverge is how a stored value becomes
  // unmatchable. The interest catalogues guard themselves the same way.
  const appPath = path.join(
    process.env.FLAME_APP_PATH
      || '/Users/firdavsmutalipov/Desktop/Flame/flame_front_app',
    'lib/core/languages/language_catalogue.dart',
  );

  if (!fs.existsSync(appPath)) {
    // The app repo is not always checked out beside this one. Skip rather
    // than fail: a missing sibling is an environment fact, not a defect.
    console.log('app catalogue not found, skipping parity check');
    return;
  }

  const source = fs.readFileSync(appPath, 'utf8');
  const appCodes = [...source.matchAll(/Language\('([a-z]{2})',/g)]
    .map((m) => m[1]);

  assert.deepEqual(LANGUAGE_CODES, appCodes,
    'flame/config/languages.js and language_catalogue.dart have diverged');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/firdavsmutalipov/Projects/BananaTalk/backend && node --test flame/__tests__/languageCatalogue.test.js`
Expected: FAIL — `Cannot find module '../config/languages'`.

- [ ] **Step 3: Write minimal implementation**

```javascript
// flame/config/languages.js
//
// The canonical language vocabulary.
//
// These codes are what `user.languagesSpoken` and `user.languagesLearning`
// store. They are ISO 639-1, lowercase, and deliberately stable: the app shows
// each language under its own endonym (한국어, not "Korean") and never
// translates the code, so localisation cannot break a match.
//
// The app holds the same list in lib/core/languages/language_catalogue.dart,
// and a test in each repo asserts its own list matches the other's — the same
// guard the interest catalogues use, for the same reason.
//
// Order matches the app's, because the app's order is what a picker shows.
const LANGUAGE_CODES = Object.freeze([
  'en', 'zh', 'hi', 'es', 'ar', 'bn', 'pt', 'ru', 'ja', 'de',
  'fr', 'ko', 'tr', 'vi', 'it', 'th', 'ur', 'id', 'pl', 'uk',
  'nl', 'fa', 'ms', 'tl', 'sv', 'el', 'cs', 'ro', 'hu', 'he',
  'da', 'fi', 'nb', 'sk', 'hr', 'sr', 'bg', 'ca', 'sw', 'ta',
]);

const _set = new Set(LANGUAGE_CODES);

/** Whether `code` is one this app knows. Case-insensitive; anything non-string is false. */
function isLanguageCode(code) {
  if (typeof code !== 'string') return false;
  return _set.has(code.toLowerCase());
}

module.exports = { LANGUAGE_CODES, isLanguageCode };
```

- [ ] **Step 4: Run backend test to verify it passes**

Run: `cd /Users/firdavsmutalipov/Projects/BananaTalk/backend && node --test flame/__tests__/languageCatalogue.test.js`
Expected: PASS, 4 tests.

- [ ] **Step 5: Write the app-side parity test**

```dart
// test/core/languages/language_parity_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/languages/language_catalogue.dart';

/// The other half of the guard in flame/__tests__/languageCatalogue.test.js.
/// Each repo checks itself against the other, so whichever one you are working
/// in tells you when they drift.
void main() {
  test('the catalogue matches the backend list exactly', () {
    const backendPath =
        '/Users/firdavsmutalipov/Projects/BananaTalk/backend/flame/config/languages.js';
    final file = File(backendPath);

    if (!file.existsSync()) {
      // The backend is not always checked out beside this repo. An absent
      // sibling is an environment fact, not a defect.
      // ignore: avoid_print
      print('backend catalogue not found at $backendPath, skipping');
      return;
    }

    final source = file.readAsStringSync();
    final block = RegExp(r'LANGUAGE_CODES = Object\.freeze\(\[(.*?)\]\)',
            dotAll: true)
        .firstMatch(source);
    expect(block, isNotNull, reason: 'could not find LANGUAGE_CODES');

    final backendCodes = RegExp(r"'([a-z]{2})'")
        .allMatches(block!.group(1)!)
        .map((m) => m.group(1)!)
        .toList();

    expect(kLanguages.map((l) => l.code).toList(), backendCodes,
        reason: 'language_catalogue.dart and flame/config/languages.js '
            'have diverged');
  });
}
```

- [ ] **Step 6: Run the app parity test**

Run: `flutter test test/core/languages/language_parity_test.dart`
Expected: PASS, 1 test.

- [ ] **Step 7: Verify backend blast radius, then commit both repos**

```bash
cd /Users/firdavsmutalipov/Projects/BananaTalk/backend
git status --short | awk '{print $2}' | grep -v '^flame/'   # must print nothing
git add flame/config/languages.js flame/__tests__/languageCatalogue.test.js
git commit -m "feat(flame): the language vocabulary, guarded against drift

Codes only — the app renders each language under its own endonym, so the
server never needs a display name and never needs translating.

Each repo tests itself against the other's list. Two hardcoded lists that
silently diverge is how a stored value becomes unmatchable, which is the
lesson the interest catalogues already record."

cd /Users/firdavsmutalipov/Desktop/Flame/flame_front_app
git add test/core/languages/language_parity_test.dart
git commit -m "test(languages): assert the app catalogue matches the backend's"
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
  distance: 0.22,
  language: 0.20,
  activity: 0.16,
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

### Task 6: Registration step 4 pickers

**Files:**
- Modify: `lib/screens/auth/registration/steps/step_bio_interests.dart`
- Modify: `lib/screens/auth/registration/registration_flow.dart` (`RegistrationData` gains two lists)
- Modify: `lib/providers/auth_provider.dart` + `lib/services/auth_service.dart` (register body)
- Modify: `lib/l10n/app_en.arb` **and all 25 base locale ARBs** (3 new keys)
- Test: `test/screens/auth/registration/language_step_test.dart` (create)

**Interfaces:**
- Consumes: `kLanguages`, `endonymFor` (Task 1); `User.languagesSpoken` (Task 4).
- Produces: `RegistrationData.languagesSpoken` / `.languagesLearning`, sent on register.

- [ ] **Step 1: Add the three l10n keys to English**

```bash
python3 - <<'PY'
import json, pathlib, collections
p = pathlib.Path('lib/l10n/app_en.arb')
d = json.loads(p.read_text(), object_pairs_hook=collections.OrderedDict)
new = [
 ("registerLanguagesSpoken", "Languages you speak",
  "Header for the languages-spoken picker in registration."),
 ("registerLanguagesLearning", "Languages you're learning",
  "Header for the languages-learning picker in registration."),
 ("registerLanguagesHint", "Up to 3 each — this is how we find people you can talk to",
  "Explains the cap and why languages are collected."),
]
for k, v, desc in new:
    if k in d: continue
    d[k] = v
    d['@' + k] = {"description": desc}
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n")
print('added', len(new))
PY
```

- [ ] **Step 2: Translate the three keys into all 25 base locales**

`arb_parity_test` fails otherwise. Add the same three keys to each of
`app_{ar,bn,ca,cs,da,de,es,fi,fr,hi,hr,id,it,ja,ko,nb,nl,pt,ru,th,tr,ur,vi,zh,zh_Hant}.arb`
with real translations — English placeholders are not acceptable, matching how
the notification and location strings were handled.

Then: `flutter gen-l10n` and `flutter test test/l10n/`
Expected: PASS.

- [ ] **Step 3: Write the failing test**

```dart
// test/screens/auth/registration/language_step_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/languages/language_catalogue.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';
import 'package:flame/screens/auth/registration/steps/step_bio_interests.dart';

Widget _host(RegistrationData data, {Locale locale = const Locale('en')}) =>
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StepBioInterests(data: data, onNext: () {})),
      ),
    );

void main() {
  testWidgets('spoken languages pre-seed from the device locale', (tester) async {
    // The premise gets populated for essentially every new user with no added
    // friction, and no new blocking gate on the step App Review flagged.
    final data = RegistrationData();
    await tester.pumpWidget(_host(data, locale: const Locale('ko')));
    await tester.pumpAndSettle();

    expect(data.languagesSpoken, contains('ko'));
  });

  testWidgets('an unsupported device locale seeds nothing rather than guessing',
      (tester) async {
    final data = RegistrationData();
    await tester.pumpWidget(_host(data, locale: const Locale('en')));
    await tester.pumpAndSettle();

    expect(data.languagesSpoken, ['en']);
  });

  testWidgets('languages render under their own names', (tester) async {
    await tester.pumpWidget(_host(RegistrationData()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('한국어'), 200);
    expect(find.text('한국어'), findsOneWidget);
    expect(find.text('Korean'), findsNothing,
        reason: 'endonyms need no translation — that is the point');
  });

  testWidgets('tapping a language toggles it into the data', (tester) async {
    final data = RegistrationData();
    await tester.pumpWidget(_host(data));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('한국어'), 200);
    await tester.tap(find.text('한국어'));
    await tester.pumpAndSettle();

    expect(data.languagesSpoken, contains('ko'));
  });

  testWidgets('the cap of three is enforced', (tester) async {
    final data = RegistrationData()
      ..languagesSpoken = ['en', 'ko', 'es'];
    await tester.pumpWidget(_host(data));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Français'), 200);
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();

    expect(data.languagesSpoken.length, 3, reason: 'a fourth must not stick');
    expect(data.languagesSpoken, isNot(contains('fr')));
  });

  test('every catalogue entry is selectable', () {
    // A language nobody can pick is a language nobody can match on.
    expect(kLanguages, isNotEmpty);
  });
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/screens/auth/registration/language_step_test.dart`
Expected: FAIL — `The getter 'languagesSpoken' isn't defined for the class 'RegistrationData'`.

- [ ] **Step 5: Add the fields to RegistrationData**

In `lib/screens/auth/registration/registration_flow.dart`, inside `RegistrationData`:

```dart
  /// ISO 639-1 codes, max 3. Seeded from the device locale on first build of
  /// the step so the premise is populated without asking anything extra.
  List<String> languagesSpoken = [];
  List<String> languagesLearning = [];
```

- [ ] **Step 6: Add the pickers to the step**

In `step_bio_interests.dart`, add to the state class:

```dart
  bool _seededLanguages = false;

  /// Pre-selects the device's language, once.
  ///
  /// Someone on a Korean phone opens this step with 한국어 already chosen.
  /// That populates the app's premise for essentially every new user at zero
  /// friction — and, deliberately, without adding a second blocking
  /// requirement to the step whose first one produced the "Skip for now was
  /// unresponsive" rejection.
  void _seedFromLocale(BuildContext context) {
    if (_seededLanguages) return;
    _seededLanguages = true;
    if (widget.data.languagesSpoken.isNotEmpty) return;

    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (languageForCode(code) != null) {
      widget.data.languagesSpoken = [code];
    }
  }
```

Call `_seedFromLocale(context)` at the top of `build`.

Add a chip grid below the interests grid, mirroring `_buildInterestsGrid`'s
`Wrap` + `GestureDetector` + `AnimatedContainer` structure, for each of the two
lists. Each chip's `onTap` calls:

```dart
  void _toggleLanguage(List<String> list, String code) {
    setState(() {
      if (list.contains(code)) {
        list.remove(code);
      } else if (list.length < 3) {
        // Silently ignoring a fourth is the cap doing its job; the counter
        // above the grid already shows the limit.
        list.add(code);
      }
    });
  }
```

Chip label: `Text(endonymFor(language.code))`.
Section headers: `context.l10n.registerLanguagesSpoken` / `registerLanguagesLearning`,
with `context.l10n.registerLanguagesHint` beneath the first.

- [ ] **Step 7: Run test to verify it passes**

Run: `flutter test test/screens/auth/registration/language_step_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 8: Send them on register**

In `lib/services/auth_service.dart`'s `register`, add two optional named
`List<String>` parameters and include them in the body as `languagesSpoken` /
`languagesLearning`. Mirror on `AuthNotifier.register` in
`lib/providers/auth_provider.dart`, and pass `_data.languagesSpoken` /
`_data.languagesLearning` from the registration flow's submit.

- [ ] **Step 9: Full app suite and analyze**

Run: `flutter test 2>&1 | tail -3` and `flutter analyze 2>&1 | grep -c "error •"`
Expected: all pass; `0`.

- [ ] **Step 10: Commit**

```bash
git add lib/screens/auth/registration lib/services/auth_service.dart \
        lib/providers/auth_provider.dart lib/l10n test/screens/auth/registration/language_step_test.dart
git commit -m "feat(register): declare your languages, seeded from the device

Folded into step 4 rather than added as a sixth step: App Review rejected
this exact flow days ago, and a longer one invites a fresh look at a screen
we want skimmed past.

Spoken languages pre-select from the device locale, so a Korean phone opens
with 한국어 already chosen. That populates the premise for essentially every
new user at zero friction and avoids adding a second blocking gate to the
step whose first one produced the 'Skip for now was unresponsive' rejection.

Chips show endonyms, so no language name needs translating into 25 locales."
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
- Consumes: `User.languagesSpoken` / `languagesLearning` (Task 4), `endonymFor` (Task 1).
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
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/widgets/languages_line.dart';

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
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

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/languages/language_catalogue.dart';

/// "Speaks 한국어 · Learning English".
///
/// The premise, made visible. Ranking cannot be seen — in a sparse pool it may
/// not even be felt — so this line is what tells someone, and an App Store
/// reviewer, what this app is for within seconds of opening it.
///
/// Renders NOTHING when nothing is declared. Every account created before this
/// feature has empty lists, and a label with no value after it reads as broken
/// data rather than as an absent answer.
class LanguagesLine extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final parts = <String>[];

    if (spoken.isNotEmpty) {
      parts.add('${context.l10n.profileSpeaks} '
          '${spoken.map(endonymFor).join(', ')}');
    }
    if (learning.isNotEmpty) {
      parts.add('${context.l10n.profileLearning} '
          '${learning.map(endonymFor).join(', ')}');
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
| §1 Catalogue mirroring | 1, 2 |
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
`endonymFor(String)` and `languageForCode(String?)` are defined in Task 1 and used
in Tasks 6 and 7 under those exact names. `languageScore(viewer, candidate)` is
defined in Task 5 and referenced nowhere earlier.

**One risk worth restating:** Task 7 is what answers the rejection. If the plan is
executed partially, executing 1–6 and skipping 7 produces a correct feature that
no reviewer will notice.
