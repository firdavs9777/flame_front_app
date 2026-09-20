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

## B. Reply to Guideline 2.1 — we were unable to sign in with the demo account

> Paste into **App Store Connect → Resolution Center**.

Thank you for flagging this, and apologies for the wasted attempt.

The credentials were correct; the sign-in form was not. Pasting the address
carried invisible characters along with it — zero-width spaces and a byte-order
mark — and the form compared the pasted string literally, so the address never
matched. Typing it by hand would have worked, which is why it passed our own
testing.

The app now strips those characters from every field where an address is typed
or pasted: sign-in, registration, and both steps of password reset. The same
credentials in App Store Connect now work when pasted.

---

## C. Reply to Guideline 4 — Sign in with Apple

> Paste into **App Store Connect → Resolution Center**.

You are right, and the cause was on our side rather than in the framework.

The app requested the `fullName` scope from Authentication Services, received
the name, and then discarded it — only the identity token and authorization
code were forwarded to our server. With no name to store, the account was
created as "New User", and the profile step then presented that placeholder for
the user to correct. That is the behaviour you saw.

Build 10003 captures `givenName` and `familyName` from the Apple credential and
forwards them, so an account created through Sign in with Apple now carries the
name Apple supplied and the user is not asked for it. The name is only ever
used to fill a gap: on later sign-ins the existing account is returned
untouched, so a name the user has since edited is never overwritten.

**One thing worth knowing before you test.** Apple returns `givenName` and
`familyName` exactly once — on the first authorization of this app by a given
Apple ID — and never again, in the token or otherwise. If you signed in to
Flame with the same Apple ID during the previous review, Apple will not send
the name a second time, and the app will have nothing to display.

To see the corrected behaviour, please either use an Apple ID that has not
signed in to Flame before, or revoke the previous authorization first:
**Settings → [your name] → Sign-In & Security → Sign in with Apple → Flame →
Stop Using Apple ID.** The next sign-in is then treated as a first
authorization and the name arrives.

We are happy to supply a dedicated Apple ID for this if that is easier.

---

## D. Reply to Guideline 2.1(a) — the Skip for now button

> Paste into **App Store Connect → Resolution Center**.

Reproduced and fixed.

The button was not unresponsive in the sense of a dropped tap — it was
disabled. The interests step required at least one selection before it would
let anyone continue, and "Skip for now" was wired to the same condition as
"Continue", so the one control that existed to bypass the requirement was
itself blocked by it. It also still rendered in its enabled colours, so there
was nothing on screen to say why tapping did nothing.

Both faults are fixed in build 10003. "Skip for now" is now always actionable,
and the shared button component now derives its colours from whether it can
actually be pressed, so a disabled control can never again look enabled. An
automated test covers the case and quotes your report, so it cannot regress.

---

## E. Reply to Guideline 2.1 — face data

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

## F. Demo account

Sign-in details go in **App Review Information**, not in the letter.

- Email: `appreview1@banatalk.com`
- Password: in App Store Connect → App Review Information (deliberately not
  written into this repository, which is public).

A note worth adding to App Review Information: the previous submission's demo
sign-in failed. The cause was invisible characters carried along when the
credentials were pasted, not the credentials themselves. The app now strips
them on every sign-in, registration and password-reset field, so pasting works.

---

## G. Before sending — checklist

Ordered. Nothing below the line about photos is worth doing until that is done.

- [ ] **1. Photos** on all three accounts (demo, both seeds), added **through
      the app** so they pass the same on-device face check as any member's.
      Everything else in this letter assumes a reviewer looking at real cards.
- [ ] **2. Name and subtitle in all 32 localizations** —
      `2026-09-resubmission-metadata.md` §1b. App Store Connect stores these
      per localization; changing only English leaves the old generic name in
      31 storefronts, which is part of what 4.3(b) objected to.
- [ ] **3. Archive and upload build 1.0.0 (10003).**
- [ ] **4. App Review Information** — demo credentials, plus the note in §F,
      plus the Apple ID revocation note from §C. A reviewer who reuses last
      review's Apple ID will not see the Sign in with Apple fix.
- [ ] **5. Walk it yourself** as the demo account, on an **iPad** — that is
      the device they reviewed on, and where the Skip button bug was found.
      Steps 1-5 of §A, and tap "Skip for now" on the interests step.
- [ ] **6. Paste §A-§E** into Resolution Center as one reply. All five issues,
      in the order Apple raised them. A reply that answers some of them reads
      as a reply to none.
- [ ] **7. Rotate the demo password** and update App Store Connect. It was
      briefly readable in a public repository.

### If you are short of time

Items 1, 3 and 6 are the submission. Item 2 can be done after submitting —
metadata is editable while the build is in review. Item 7 can be done
immediately after. Item 5 cannot be skipped: every claim in §A is an
invitation to go and look.
