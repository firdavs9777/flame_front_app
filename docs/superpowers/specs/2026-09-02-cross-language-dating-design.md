# Cross-language dating — differentiating Flame under Guideline 4.3(b)

**Date:** 2026-09-02
**Status:** approved
**Scope:** app (`flame_front_app`) + backend (`language_exchange_backend_application/flame`) + App Store metadata

## Why this exists

App Review rejected Flame under **Guideline 4.3(b) — Design: Spam**:

> The app primarily includes dating features that duplicate the content and
> functionality of similar apps that are already widely available. […] there are
> already enough of these apps on the App Store.

This is not a bug report. No amount of fixing the other four rejection items
answers it, because 4.3(b) is a judgement about the app's **concept**, formed in
the first minute of use. The test every decision below is measured against:

> Would a reviewer, ninety seconds in, struggle to call this a Tinder clone?

Anything that fails that test does not clear the rejection, however much work it
represents.

## The premise

**Flame is for meeting people you could not otherwise talk to.**

Not "a dating app with a translate button" — the translation is the point, not a
feature list entry. Someone who speaks Korean and is learning English is shown
someone who speaks English and is learning Korean, told why, and dropped into a
chat that translates by default.

### Why this angle rather than another

Because Flame already owns the expensive parts, and its competitors do not:

- `/translate` is live and wired into `message_bubble.dart`.
- The app ships **25 base locales**.
- BananaTalk — same developer, same backend host — already proves the data
  model, with `native_language`, `language_to_learn`, and an index commented
  `// For language matching`.

The alternative considered and rejected for now was retiring the swipe deck
entirely in favour of a conversation-first loop. That is a stronger 4.3 answer
and a much larger, riskier build; it stays on the table if this does not clear.

## Decisions taken, and why

### Language compatibility RANKS the deck. It does not filter it.

`discoveryService` already made this call for interests and wrote down the
reason:

> Any overlap, not all: requiring every selected interest empties the deck on a
> small user base, and this app has a small user base.

The same physics apply harder here — language pairs are scarcer than interests.
A filtered deck would be a sharper product and an easier story to tell Apple,
and it would also show a lot of users nothing at all. A dating app with no cards
is worse than a generic one.

**The consequence must be designed around:** ranking is invisible, especially in
a sparse pool. A reviewer with a fresh account may see no reordering whatsoever.
That is why the visibility work in §4 is not decoration — it is the part that
actually answers the rejection.

### Two lists, not one native language

`languagesSpoken` and `languagesLearning`, capped at three each.

A single native language would halve the matching surface on a user base that
cannot spare it: two people who would never pair on one declared language often
pair on a list. Complementarity — *I speak English and I am learning Korean; you
speak Korean and you are learning English* — is the whole insight, and it needs
both directions to express.

### Display names are endonyms, not translations

Each language shows in its own name: 한국어, Español, Français, English.

The established pattern in this repo is `interest_catalogue.dart`: a stable
English token plus a localised label per locale. Following it here would mean
roughly forty languages against 25 locales — a thousand strings to translate and
keep in sync, enforced by `arb_parity_test`.

Endonyms need **zero** translation, never drift, and are more legible to the
person who actually speaks the language. It is also what language pickers
conventionally do.

The token stored stays an ISO 639-1 code and is never translated, for exactly
the reason the interest catalogue gives about its own tokens: translating a
stored value breaks every record and every match at once.

**The endonyms are not written by hand.** BananaTalk's `_data/languages.json`
already carries a `nativeName` column for 182 languages, correct for every code
this shortlists, and the catalogue is generated from it. Retyping 한국어 and
العربية from memory is how a display name acquires a typo nobody on the team
can see.

The data is copied, not fetched. `GET /languages` exists on the BananaTalk side
and would be a single source of truth, but this is static data: calling it at
runtime would add a network failure mode to the registration screen App Review
just rejected, and couple flame to a route `CLAUDE.md` says to stay clear of.

**No flag emoji**, despite the BananaTalk picker using them. Flags mark
countries, not languages — 🇺🇸 for English erases every other English-speaking
country, and Swahili, Arabic and Tagalog have no defensible single flag. On an
app about meeting people from elsewhere, that is a poor first impression.

### Declared inside registration step 4, pre-seeded from the device locale

Registration stays at **five steps**. Apple rejected this exact flow four days
ago on a different issue; a resubmission that also lengthens it invites a fresh
look at a screen we want skimmed past.

Spoken languages open **pre-selected from the device locale** — a Korean phone
arrives with 한국어 already chosen. This matters more than it appears:

- The premise gets populated for essentially every new user, with no added
  friction and no new blocking requirement on the screen under scrutiny.
- It avoids adding a second "you must pick something" gate to the step whose
  first gate produced the *"Skip for now was unresponsive"* rejection.

Learning languages stay optional. Someone monolingual and not learning anything
is a legitimate user, not an incomplete one.

### Unknown is neutral, never bad

Every existing account has no language data, and neither does the App Review
demo account. Scoring them zero would bury the entire current user base for a
field that did not exist when they signed up.

This matches the rule already applied to unknown distance, absent interests and
unset preferences in `rankingService`.

## 1. Data model

**App** — `User` gains:

```
languagesSpoken:   List<String>   // ISO 639-1, max 3
languagesLearning: List<String>   // ISO 639-1, max 3
```

**Backend** — the same two fields on `flame/models/User.js`, defaulting to `[]`,
validated at a maximum of three entries each and against the catalogue. Added to
the profile-update `PATCHABLE` set and to the discovery wire shape as
`languages_spoken` / `languages_learning`.

**Catalogue** — `lib/core/languages/language_catalogue.dart`: ISO code plus
endonym, mirrored by `flame/config/languages.js` so the server can reject codes
the client would never send. Mirroring is the pattern `interest_catalogue`
already establishes with `flame/config/interests.js`.

No migration. Absent fields read as empty lists, and every consumer treats empty
as unknown — see §3.

## 2. Onboarding

Two capped chip multi-selects added to `step_bio_interests.dart`, below
interests, reusing the chip pattern already on that screen.

Buttons keep the contract established on 2026-09-02: **nothing on this step is
ever disabled**. Requirements are stated inline before a tap, and every tap gets
a response.

Existing users are prompted from their profile, never forced.

## 3. Ranking

A sixth component in `rankingService`. Weights sum to 1, so all of them move:

| component | before | after |
|---|---|---|
| interests | 0.30 | 0.22 |
| distance | 0.25 | 0.22 |
| **language** | — | **0.20** |
| activity | 0.20 | 0.16 |
| reciprocity | 0.15 | 0.12 |
| completeness | 0.10 | 0.08 |

`languageScore(viewer, candidate)` measures **complementarity**, not sameness.
Stated as concrete values, because "mild positive" is not implementable:

| situation | score |
|---|---|
| mutual exchange — each speaks what the other is learning | **1.00** |
| one direction — they speak something the viewer is learning | **0.85** |
| one direction — the viewer speaks something they are learning | **0.75** |
| no exchange, but a shared spoken language | **0.55** |
| no exchange and no shared language | **0.35** |
| either side has declared nothing | **0.50 — neutral** |

Two asymmetries are deliberate:

- **0.85 over 0.75.** Being shown someone who speaks what you are learning is
  more valuable to *you*, the viewer, than being shown someone who wants what
  you already have. The deck is ordered for the viewer.
- **0.35, not 0.** No shared language and no exchange is the weakest pairing,
  but translation still makes the conversation possible — so it is a demotion,
  not an exclusion. Zero would be filtering by the back door, which §"RANKS,
  does not filter" rules out.

Note that 0.50 (no data) scores *above* 0.35 (declared, no overlap). That is
intentional: an unknown must never rank below a known-poor match, or the
existing user base would be penalised for having declared nothing.

0.20 is deliberately below `interests` at 0.22. The premise should shape the
deck, not dictate it — someone with nothing in common but a convenient language
pair is not a better match than someone who shares your life.

## 4. Visibility — the section that answers the rejection

Ranking cannot be seen. In a sparse pool it may not even be felt. The premise
must therefore be legible on screen without a single match existing:

- **Deck card** — `speaks 한국어 · learning English`, visually distinguished when
  it complements the viewer.
- **Chat** — when two people's spoken languages do not overlap, translation is
  **on by default** and says so, rather than hiding behind a long-press.
- **Profile** — a languages row, on both own-profile and detail.

**The App Review demo account must have languages set**, and photos. It is the
only account the reviewer will use; if it renders none of this, the
differentiation does not exist as far as the rejection is concerned.

## 5. Metadata

Not optional, and not sufficient alone. **"Flame Dating App: Meet & Date"** is
the most generic submission possible and reads as evidence for the rejection it
received. To be drafted and submitted alongside the build:

- name and subtitle leading with the cross-language premise
- description whose first two lines state what is different
- first two screenshots showing a language-complementary card and a translated
  conversation — not a swipe deck

## Testing

| Area | Pinned |
|---|---|
| `languageScore` | complementarity beats sameness; both-directions beats one; **no data ranks neutral, not last** |
| Weights | still sum to 1 |
| Catalogue | app and backend lists agree; every stored code resolves to an endonym |
| Onboarding | device locale pre-seeds; caps enforced; nothing disabled |
| Backend | round-trip through profile update; over-long lists and unknown codes rejected |
| Regression | a user with no language data ranks exactly as before |

Both suites green, `flutter analyze` error-clean, both platforms building.

## Deliberately not built

- **Language filtering.** Decided against — see §"RANKS, does not filter".
- **Proficiency levels.** A/B/C1 self-ratings are noise until the premise proves
  itself, and they make onboarding materially heavier.
- **Auto-detecting language from typed text.** The user just told us what they
  speak.
- **Retiring the swipe deck.** The stronger 4.3 answer, deliberately deferred.

## Honest risk

The core loop remains a swipe deck. This makes it a **differentiated** swipe
app, not a different kind of app, and a reviewer may still class it under 4.3(b).
Nobody can promise otherwise, and the metadata in §5 carries more of the weight
than its size suggests.

If this is rejected again on 4.3(b), the remaining move is the larger one:
replace the deck with a conversation-first loop.
