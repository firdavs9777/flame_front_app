# Response to App Review — build 1.0.0 (10003)

Every factual claim below was re-checked against the shipped app, and against
production, on the day of writing. **Do not add a claim to this text without
doing the same.** An earlier draft told Apple the deck card is "visually
distinguished when languages complement" while nothing of the sort had been
built; a reviewer who follows a pointer and finds nothing has been handed a
reason to reject. That highlight now exists — which is why step 2 below can
name it — but the rule that produced the mistake has not changed.

**Send this only after the demo account and the two seed accounts have
languages and photos** (`2026-09-resubmission-metadata.md` §7). The whole letter
is an invitation to go and look; if the reviewer looks and the screens are
empty, it does more harm than sending nothing.

---

## A. Reply to Guideline 4.3(b) — Design: Spam

> Paste into **App Store Connect → Resolution Center**.

Thank you for the review.

We understand the concern. A dating app that matches only on photos and
distance is hard to distinguish from many others already on the App Store, and
that was a fair description of the build you reviewed.

We have not answered this with cosmetic changes. Flame's matching premise is
now cross-language dating: members are matched on how their languages
complement one another, and a conversation between two people with no shared
language is translated automatically rather than requiring them to ask for it.

What is in build 10003, all of it verifiable in the app:

1. **Members declare the languages they speak and the languages they are
   learning.** This is part of creating an account, and existing members can
   set it from Edit Profile. The catalogue is 182 languages, shown with their
   own endonyms (Oʻzbek, ئۇيغۇرچە, 한국어) rather than English names.

2. **Those declarations are a weighted input to matching, not a filter or a
   badge.** Language complementarity carries 0.20 of the ranking score,
   alongside shared interests, distance, recent activity and mutual
   preference-compatibility. Someone who speaks what you are learning, and is
   learning what you speak, ranks above someone equally close and equally
   active who does not.

3. **The languages are visible where the decision is made** — on the profile
   card in the deck, on the full profile, and on the member's own profile —
   each language shown with its flag. Where the fit is mutual, the card says
   so: a card whose owner speaks what you are learning *and* is learning what
   you speak is marked "You can teach each other". That is the one case the
   ranking scores highest, and it is marked only in that case, so the label
   means something when it appears.

4. **Chat translates by default across a genuine language gap.** When both
   people have declared spoken languages and share none, incoming messages
   arrive already translated, marked with a translation icon and a "Hide
   translation" control. Where the two share a language, nothing is
   translated and the manual per-message option remains exactly as it was. We
   default on only for a *known* mismatch: an undeclared language is not
   evidence of a gap, and translating for two people who in fact share a
   language would be a defect, not a feature.

We have also renamed the app. "Flame Dating App: Meet & Date" stated the
category and nothing else; it is now "Flame: Date Across Languages", with the
subtitle "Chat translates automatically", so the premise is stated where a user
first meets the app rather than discovered after signing up.

**To confirm this in about two minutes**, signed in as the demo account below:

1. Open **Discover**. The cards show each person's languages — the demo
   account's matches include a Korean speaker learning English and a Spanish
   speaker learning English, which is what the ranking is preferring.
2. Both of those cards carry a **"You can teach each other"** marker, because
   each of them speaks a language the demo account is learning and is learning
   the language it speaks. It is the ranking's reasoning, shown on the card.
3. Tap a card to open the full profile and see the same languages in full.
4. Open a conversation with either of them. Because the demo account speaks
   English and neither of them does, their messages appear **already
   translated**, with a "Hide translation" control — no tap needed.
5. Open **Profile → Edit Profile → Languages** to see and change the
   declaration that drives all of the above.

We are glad to answer anything further.

---

## B. Reply to Guideline 2.1 — face data

> Paste into the **App Privacy / Resolution Center** response, or the face-data
> questions if asked as a form.

Flame uses on-device face detection for one purpose: to check that a photo a
member is uploading as a profile photo actually contains a human face.

- **What is collected.** A camera or gallery image the member has chosen is
  analysed in memory, on their own device, to detect whether a face is present,
  plus coarse quality signals (eyes open, smiling) used only to reject an
  unclear photo. No facial landmark data, faceprint, or biometric template is
  created.
- **How it is used.** Solely to accept or reject that photo as a profile photo.
  There is no other use, and none planned.
- **Sharing.** None. The analysis is performed by Google ML Kit running locally
  on the device. No image or derived data is transmitted to Google, to us, or
  to any third party for this check.
- **Retention.** None. The pass/fail result is used at that moment and is not
  stored. The photo itself, once accepted, is stored as an ordinary profile
  photo and is deleted through the normal photo and account deletion flows.
- **Storage.** None. Processing is transient and in memory.
- **Deletion.** Not applicable — nothing derived from face detection is
  retained, so there is nothing to delete beyond the profile photo itself.

This is disclosed in our privacy policy under "Photos and face detection":

> "We do not run face recognition, do not compute a faceprint or any biometric
> identifier, and do not compare your face against any database. Photos are not
> sent anywhere for this check."

---

## C. Demo account

Sign-in details go in **App Review Information**, not in the letter.

- Email: `appreview1@banatalk.com`
- Password: in App Store Connect → App Review Information (deliberately not
  written into this repository, which is public).

A note worth adding to App Review Information: the previous submission's demo
sign-in failed. The cause was invisible characters carried along when the
credentials were pasted, not the credentials themselves. The app now strips
them on every sign-in, registration and password-reset field, so pasting works.

---

## D. Before sending — checklist

- [ ] Backend deployed (done — the language catalogue is live in production).
- [ ] §7a run: demo account has `languagesSpoken: ["en"]`, `languagesLearning:
      ["ko","es"]`. **Verify by reading it back** — the update endpoint accepts
      camelCase and silently discards a snake_case typo with a 200.
- [ ] §7b: both seed accounts exist, within the demo account's discovery
      radius, with bios.
- [ ] §7c: demo account and both seed accounts have at least one photo, added
      through the app so they pass the same face check as any member.
- [ ] Signed in as the demo account, walked steps 1–5 of the letter and seen
      each one actually work — including the "You can teach each other" marker
      on both seed accounts' cards, which only appears once §7a and §7b have
      given all three accounts their languages. **If any step does not, fix it before sending
      rather than softening the wording** — every step is checkable, which is
      the point.
- [ ] Name and subtitle updated in App Store Connect.
- [ ] Build 10003 uploaded.
