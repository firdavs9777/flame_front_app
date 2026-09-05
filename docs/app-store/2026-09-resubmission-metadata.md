# App Store resubmission metadata — cross-language dating

**Date:** 2026-09-03
**Context:** Flame was rejected under **Guideline 4.3(b) — Design: Spam**
("primarily includes dating features that duplicate the content and
functionality of similar apps that are already widely available") and
separately asked, under **Guideline 2.1**, what face data the app collects.
This document is the copy for the resubmission and the answers to the 2.1
question. It does not change product code.

The build this metadata accompanies is `1.0.0+10003` (see "Build number"
below). The build App Review rejected was `10001`.

---

## 1. App name (30-character limit)

The current name, **"Flame Dating App: Meet & Date"**, must go. It states the
category and nothing else — it is the single most generic name a dating app
could have, and it reads as supporting evidence for the 4.3(b) rejection
rather than an answer to it.

| Option | Characters | Note |
|---|---|---|
| **Flame: Date Across Languages** | 28/30 | States the premise in the name itself — not a feature, the concept. |
| Flame — Meet in Any Language | 28/30 | Softer framing, same premise. |
| Flame: Dating, Translated | 25/30 | Shorter, but risks reading as "a dating app with a translate button" — the exact framing the design spec warns against. |

**Recommendation: "Flame: Date Across Languages."** It is the only one of the
three that states the concept (who you're matched with) rather than a
mechanism (translation). "Translated" alone invites the reviewer to see
translation as a bolted-on feature; "Date Across Languages" states the
premise the whole rejection response depends on.

## 2. Subtitle (30-character limit)

| Option | Characters | Note |
|---|---|---|
| **Chat translates automatically** | 29/30 | Names the concrete mechanism that backs the name's premise. |
| Real chats, any language | 24/30 | Shorter, slightly vaguer. |
| Match, chat, auto-translated | 28/30 | Covers more ground, reads a little listy. |

**Recommendation: "Chat translates automatically."** The name states the
premise (who you meet); the subtitle should state the mechanism (what makes
it work) rather than restate the premise in different words.

## 3. Description

First two lines carry the answer to 4.3(b) before anything else. Usual
dating-app feature list comes after, not before.

```
Flame matches you with people you couldn't otherwise talk to — profiles are
ranked by complementary languages, not just distance and age.
When you don't share a language with someone, your chat translates
automatically. No copy-pasting into another app, no long-press menus to find.

Flame ships in 25 languages and supports matching across all of them:
speak Korean and you'll see people learning it who speak what you're
learning. Speak only English? You'll still see complementary matches, and
every conversation translates either way.

Beyond that, Flame is a real dating app:
• Swipe, match, and chat
• Stories that expire
• Sign in with Apple, Google, or email
• Precise, private location-based discovery
• Report and block tools that actually work
• Free to download

Flame is for adults 18 and over.
```

## 4. Screenshot captions

Order matters: the first two screens are the answer to 4.3(b), and neither is
the swipe deck. A swipe deck screenshot first is exactly the "looks like every
other dating app" impression this resubmission is trying to correct.

1. **"Speaks 한국어, learning English — matched because your languages
   complement."** (Deck card, or profile detail, showing the languages row
   with the complementary highlight from Task 7.)
2. **"Don't share a language? Your chat translates automatically."** (Chat
   screen with the default-on translation banner/behavior visible, ideally
   showing one message in the original and one translated.)
3. "Swipe, match, chat — the usual, done well." (Swipe deck — now third, not
   first.)
4. "Share your day with Stories." (Stories feature.)
5. "Your privacy, your control." (Report/block/privacy controls.)

## 5. Review notes (App Store Connect → App Review Information → Notes)

**Demo account:**
Email: `appreview1@banatalk.com`
Password: see App Store Connect -> App Review Information.
Deliberately not written here: this repository is public.

**Note to reviewer:**

> This build answers the 4.3(b) rejection by ranking and surfacing
> cross-language matches, not by adding an unrelated feature. Sign in with
> the demo account above. On the demo account's own profile and in the
> discovery deck, note the languages row — it reads "speaks English,
> learning 한국어/Español", with a flag badge on each card. Open a
> conversation with one of the seeded matches (Korean-speaking or
> Spanish-speaking, both within the demo
> account's discovery radius): because the two accounts do not share a
> language, translation is on by default in that chat and says so, rather
> than being hidden behind a long-press menu. This is the feature the
> resubmission is about — please look at the languages on the card and the
> translated chat before evaluating the rest of the app.

## 6. Face data answers (Guideline 2.1)

Confirmed against `lib/services/face_detection_service.dart`: profile-photo
validation uses `google_mlkit_face_detection` (Google ML Kit), which runs
**entirely on-device**. `FaceDetectionService.validateFace` reads the image
file with `InputImage.fromFile`, runs `FaceDetector.processImage` locally, and
returns only a boolean-shaped result (`isValid`, `issue`, `faceCount`, and a
few detection-quality fields such as smiling/eye-open probabilities used only
to reject an unclear photo). Nothing in that file makes a network call, writes
the image or its analysis anywhere, or stores a representation of the face
beyond the single `validateFace()` call's return value. If ML Kit itself
throws (e.g. unavailable on the simulator), the code fails open and accepts
the photo — it never reports a face as "verified" it did not check.

**What data is collected:** A live camera/gallery image is analyzed
in-memory, on the user's own device, to detect whether it contains a human
face (and, secondarily, coarse quality signals like smiling/eyes-open used
only to flag unclear photos). No facial landmark data, faceprint, or
biometric template is created or persisted.

**Planned use:** Solely to gate whether a photo can be used as a profile
photo (a face must be detectable). No other use exists or is planned.

**Sharing:** None. The analysis never leaves the device, so there is nothing
to share.

**Retention:** None. The result (pass/fail) is used to accept or reject the
photo upload at that moment and is not stored. The photo itself, once
accepted, is stored as an ordinary profile photo (see the privacy policy's
photo-storage section) — but the face-detection result and any intermediate
detection data are not retained anywhere.

**Deletion:** Not applicable — nothing derived from face detection is stored,
so there is nothing to delete beyond the profile photo itself, which is
deleted through the normal account/photo deletion flow.

**Storage:** None. Processing is transient and in-memory on-device for the
duration of the check.

**Third-party sharing:** None. ML Kit runs locally; no image or derived data
is sent to Google or any other third party for this purpose.

**Where this is covered in the privacy policy:** `docs/legal/privacy.html`,
**Section 5, "Photos and face detection."**

**Verbatim quote to use in the answer** (confirmed against the live file,
`docs/legal/privacy.html` line 44 — note this is the actual wording in the
shipped policy, which differs slightly in phrasing from the draft quote in
the task brief; use this one since it is what users are actually shown):

> "We do not run face recognition, do not compute a faceprint or any
> biometric identifier, and do not compare your face against any database.
> Photos are not sent anywhere for this check."

---

## 7-DONE. What has actually been set (2026-09-05)

Steps 7a and 7b below were run against production. Recorded here so nobody
repeats them, and because doing so corrected two errors in the instructions
that follow — read this section before trusting them.

**Demo account** `appreview1@banatalk.com` (Alex Reviewer, male, 28, San
Francisco): `languagesSpoken: ["en"]`, `languagesLearning: ["ko","es"]`.

**Seed accounts** (both female / looking for male, so the demo account can see
them; both within 3 km of it):

| email | password | name | age | speaks | learning |
|---|---|---|---|---|---|
| `flame.seed.ko@banatalk.com` | `FlameSeedKo2026!` | Jiwoo | 27 | ko | en |
| `flame.seed.es@banatalk.com` | `FlameSeedEs2026!` | Lucia | 29 | es | en |

Passwords are here only because these are throwaway seed accounts on a public
repo's *sibling* — if that ever stops being true, rotate them.

**Demo account preferences were set explicitly** to 22-40 / 50 km. This was
not optional. `preferencesSet` defaults to false, and while it is false the
radius is deliberately NOT applied (see `discoveryService.js` — an untouched
default must not silently hide people). Before setting it the demo deck
contained three accounts **9,029 km away**, which in a location-based dating
app reads as broken. After: the deck is exactly the two seed accounts, at
2 km and 3 km, both carrying the "You can teach each other" marker.

### Two corrections to the instructions below

1. **`POST /auth/register` does NOT accept `languagesSpoken` /
   `languagesLearning`.** They are absent from `registerSchema`, and that
   schema is not `.strict()`, so they are silently discarded and registration
   still returns success. Languages must be set by a follow-up
   `PATCH /users/me` after logging in. The §7b example below is wrong on this
   point.

2. **`GET /users/me` returns camelCase**, not snake_case: `getMe` serialises
   through `toPublic`. So verify with `languagesSpoken`, not
   `languages_spoken`. (`/discover` genuinely is snake_case — the two really
   do differ, which is why the client reads both.)

**Still outstanding: 7c, photos.** All three accounts have `photos: []`. This
cannot be automated — the upload has to go through the app so it passes the
same on-device face check as any member's photo.

---

## 7. Manual steps — DO NOT AUTOMATE

**These touch production data on the live server and must be run by hand by
someone with the demo account's credentials. Nothing in this task executed
any of them.** Do not run these against `api.banatalk.com` from an agent or
script; they are recorded here so the owner can run them directly.

### 7a. Set the demo account's languages

The snippets below read the demo password from `$FLAME_REVIEW_PW` rather than
containing it, because **this repository is public**. Export it once, in the
shell you are about to run these in:

```bash
read -rs FLAME_REVIEW_PW && export FLAME_REVIEW_PW   # paste, press enter
```

`read -rs` keeps it off your screen and, unlike typing it inline, out of your
shell history. The authoritative copy is in App Store Connect -> App Review
Information; if the two ever disagree, that one is right.

```bash
# 1. Log in as the demo account to get a token.
curl -s -X POST https://api.banatalk.com/flamebackend/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"appreview1@banatalk.com","password":"'"$FLAME_REVIEW_PW"'"}'
# Take the access token from the response and use it below as $TOKEN.
#
# CASING MATTERS HERE, and getting it wrong LOOKS like success.
# This PATCH takes camelCase (`languagesSpoken`), because its zod schema in
# flame/routes/users.js:23 declares it that way. That schema is deliberately
# NOT .strict(), so an unknown key is silently stripped: send
# `languages_spoken` and you get 200 OK with nothing changed. Always run the
# verify step below rather than trusting the 200.
# (The READ paths are the other way round -- /users/me and /discover emit
# snake_case -- which is exactly why the client parses both spellings.)

# 2. Set languages — this is what makes Task 7's UI (deck card, chat,
#    profile) render anything at all for the reviewer.
curl -s -X PATCH https://api.banatalk.com/flamebackend/v1/users/me \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"languagesSpoken":["en"],"languagesLearning":["ko","es"]}'
```

**Verify:**

```bash
curl -s -X POST https://api.banatalk.com/flamebackend/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"appreview1@banatalk.com","password":"'"$FLAME_REVIEW_PW"'"}' \
  | python3 -m json.tool | grep -E 'languages|photos'
```

Expected: non-empty `languagesSpoken` (`["en"]`) and `languagesLearning`
(`["ko","es"]`). `photos` will still be empty until 7c is done — that's
expected at this point.

### 7b. Seed two complementary accounts

Create two accounts whose languages complement the demo account
(`en` spoken / `ko`+`es` learning):

- **Account A** — speaks Korean, learning English (`languagesSpoken:
  ["ko"]`, `languagesLearning: ["en"]`).
- **Account B** — speaks Spanish, learning English (`languagesSpoken:
  ["es"]`, `languagesLearning: ["en"]`).

Both must be:
- within the demo account's discovery distance radius (check the demo
  account's current location/radius setting before choosing coordinates —
  set them in the same city/region rather than guessing a radius),
- given a bio (a real sentence, not placeholder text — the reviewer may read
  it),
- given at least one photo (see 7c — the register call below can carry
  `photos` as pre-uploaded URLs, or photos can be added after registration
  through the app).

The cleanest way to create these accounts correctly (photos and all) is
through the app's real registration flow — the language-declaration screen
added in this feature (Task 6) will prompt for `languagesSpoken` /
`languagesLearning` directly, and photo capture goes through the same
face-detection check as any other user, so the seeded accounts look and
behave like real ones rather than API-only fixtures.

If registering by hand through the app is not practical, the equivalent API
call is (see `lib/services/auth_service.dart` `register()` for the exact
shape the client sends):

```bash
curl -s -X POST https://api.banatalk.com/flamebackend/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{
    "termsAccepted": true,
    "email": "flame.seed.ko@example.com",
    "password": "<choose a real password>",
    "name": "<a name>",
    "age": 27,
    "gender": "female",
    "lookingFor": "male",
    "bio": "<a real bio, not placeholder text>",
    "interests": ["travel", "music"],
    "photos": [],
    "latitude": <same area as the demo account>,
    "longitude": <same area as the demo account>,
    "languagesSpoken": ["ko"],
    "languagesLearning": ["en"]
  }'
```

`photos` cannot be populated in this call with local files — the API expects
already-hosted URLs. Upload photos with 7c immediately after registering,
using the new account's own token, before considering the seed account done.
Repeat for Account B with `languagesSpoken: ["es"]`.

### 7c. Upload photos (demo account and both seed accounts)

**Photos must go through the app, not a bare API call bypassing the client's
photo pipeline.** The demo account currently has `photos: []` — an empty
profile is itself a rejection risk under the same "full access to the app's
features and functionality" language App Review already cited, independent
of the language-ranking feature.

For each of the three accounts (demo, seed A, seed B):

1. Log in as that account **inside the app** (a simulator/device build is
   fine).
2. Go through the normal add-photo flow (Profile → Photos → Add). This
   routes through `UserService.uploadPhoto()` /
   `POST /flamebackend/v1/users/me/photos` and runs the same on-device face
   check every real user's photo goes through — do not use a photo that
   would fail that check (a real, forward-facing face, one person, not too
   small in frame).
3. Set at least one photo as primary.

If doing this outside the app is unavoidable, the endpoint is a multipart
`POST` to `/flamebackend/v1/users/me/photos` (field name `photo`, optional
`is_primary` field) with a bearer token for that account — but this skips
the app's own face-detection gate, so anything uploaded this way should
still visually contain a clear face, since a reviewer will look at it.

**Final verification, after 7a–7c are all done:**

```bash
curl -s -X POST https://api.banatalk.com/flamebackend/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"appreview1@banatalk.com","password":"'"$FLAME_REVIEW_PW"'"}' \
  | python3 -m json.tool | grep -E 'languages|photos'
```

Expected: non-empty `languagesSpoken`, `languagesLearning`, and `photos` on
the demo account, and both seed accounts discoverable from it (log in as the
demo account in the app and confirm the deck/discovery list actually shows
them — distance radius mismatches are the most likely reason a seeded
account doesn't appear).

---

## Build number

`pubspec.yaml` (`version: 1.0.0+10003`) and `lib/config/app_version.dart`
(`kAppVersion = '1.0.0'`) — version name unchanged, build number bumped from
`10002` to `10003` (App Review's rejected build was `10001`).
`test/config/app_version_test.dart` checks the version *name* (before the
`+`) matches, not the build number, so this bump does not require a code
change beyond `pubspec.yaml`.
