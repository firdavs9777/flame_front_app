# Scope C2 — Email Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans.

**Goal:** Email that actually sends — localized, preference-respecting,
unsubscribable — and a Settings screen that manages every notification channel.

**Architecture:** The existing `sendEmail`/`emailService`/`emailScheduler` trio
stays; it is wired up rather than replaced. Jobs are pure functions over an
injected clock where possible. Every path stays inert without Mailgun config, so
the suite never hangs on a pending timer.

**Tech Stack:** Node/Express/Mongoose, node:test + supertest +
mongodb-memory-server; Flutter/Riverpod, flutter_gen l10n (13 locales).

**Spec:** `docs/superpowers/specs/2026-08-23-scope-c-notifications-design.md`

## Global Constraints

- Nothing sends without `FLAME_MAILGUN_API_KEY` + `FLAME_MAILGUN_DOMAIN`.
  `isConfigured()` already gates this; keep it that way — a pending `setTimeout`
  hangs `node --test`.
- flame must NEVER use BananaTalk's `MAILGUN_API_KEY`. Separate key, separate
  domain, per the note in `flame.env.example`.
- Transactional mail (welcome, password-changed) carries NO unsubscribe link.
  Non-transactional mail always does, plus a `List-Unsubscribe` header.
- Email preferences are NOT gated by the push `enabled` toggle. Separate channels.
- All 13 locales for new app strings. Email copy: `en` mandatory, others
  falling back per key.
- `flutter analyze` 0 errors / 0 warnings; backend suites green (re-run any sweep
  failure individually — three different suites have flaked under load).
- Backend `main` auto-deploys on push.

---

### Task 1: A locale on the user

**Files:**
- Modify: `flame/models/User.js`, `flame/routes/users.js`, `flame/services/userService.js`
- Test: `flame/__tests__/userLocale.test.js`

**Interfaces:**
- Produces: `User.locale` (String, default `'en'`), accepted by
  `PATCH /users/me` and returned by `toPublic`/`toMe`.

- [ ] **Step 1: Failing test** — a new user defaults to `en`; `PATCH /users/me`
      with `{locale:'ko'}` persists it; an unknown tag is rejected 422 rather
      than stored (a junk locale silently means English forever).
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.** Validate against the app's 13 supported tags.
- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Commit.**

### Task 2: The app tells the server its language

**Files:**
- Modify: `lib/services/user_service.dart`, `lib/screens/settings/language_screen.dart`
- Test: `test/screens/settings/language_sync_test.dart`

- [ ] **Step 1: Failing test** — changing language calls the API with the new
      tag; a failed call does NOT revert the local change (the app should stay in
      the language the user picked even if the sync fails).
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.** Fire-and-forget, like `sendWelcome`: email language
      is not worth blocking a UI change on.
- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Commit.**

### Task 3: Localized email copy

**Files:**
- Create: `flame/email_templates/en.json`, plus `ko`, `ja`, `zh`, `es`, `fr`, `de`, `ru`, `pt`, `pt_BR`, `id`, `tr`
- Modify: `flame/utils/emailTemplates.js`
- Test: `flame/__tests__/emailTemplates.test.js`

**Interfaces:**
- Produces: `render(templateName, locale, vars)` → `{subject, html, text}`.

- [ ] **Step 1: Failing test** — `ko` returns Korean; an unknown locale falls
      back to `en`; a key missing from `ko` falls back to `en` FOR THAT KEY while
      the rest stays Korean; every catalog has the same key set as `en`.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.** Keep the existing pure-function shape — no I/O in
      the renderer beyond loading catalogs once.
- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Commit.**

### Task 4: Unsubscribe

**Files:**
- Create: `flame/routes/emailUnsubscribe.js`, `flame/services/unsubscribeService.js`
- Modify: `flame/index.js`, `flame/utils/sendEmail.js` (List-Unsubscribe header)
- Test: `flame/__tests__/emailUnsubscribe.test.js`

**Interfaces:**
- Produces: `signFor(userId, category)`, `verify(userId, category, sig)`,
  `GET /email/unsubscribe?u=&c=&s=` (public).

- [ ] **Step 1: Failing test** — a valid signature flips the preference; a
      tampered one does not AND returns a response indistinguishable from
      success (telling a prober which ids exist is worse than a wasted click);
      an unknown category is refused; one click is enough, with no confirmation
      step; the response is a page, not JSON.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.** HMAC-SHA256 over `u|c`, constant-time compare.
- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Commit.**

### Task 5: Preferences that mean something

**Files:**
- Modify: `flame/models/User.js`, `flame/routes/notifications.js`, `flame/services/userService.js`
- Test: `flame/__tests__/notificationPreferences.test.js`

- [ ] **Step 1: Failing test** — `promotions` defaults false and round-trips
      through the settings route; `reengagement` defaults TRUE (a service email
      about your own account, so opt-out); the three dead fields are gone; an
      existing document without the new fields reads back defaults rather than
      undefined.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.** Delete `newMatches`, `newMessages`, `superLikes` —
      nothing has ever read them. Keep and wire `promotions`; add `reengagement`.
- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Commit.**

### Task 6: The password-changed email nobody sends

**Files:**
- Modify: `flame/services/authService.js`
- Test: `flame/__tests__/passwordChangedEmail.test.js`

- [ ] **Step 1: Failing test** — changing a password sends it; a send failure
      does not fail the password change (the password IS changed; an email is not
      worth a 500); it carries no unsubscribe link, being transactional.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement**, mirroring `sendWelcome`'s fire-and-forget `.catch`.
- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Commit.**

### Task 7: Inactivity re-engagement

**Files:**
- Create: `flame/jobs/inactivityEmailJob.js`
- Modify: `flame/models/User.js` (`reengagementSent: [Number]`)
- Test: `flame/__tests__/inactivityEmailJob.test.js`

**Interfaces:**
- Produces: `daysSince(date, now)`, `thresholdFor(days)`,
  `runInactivityCheck({now})`.

- [ ] **Step 1: Failing test** — table-driven over `daysSince`/`thresholdFor`
      with an injected `now`, no database; a user at 7 days gets the 7-day mail
      once and never again, including after crossing 7 days a second time; a
      user with `reengagement:false` gets nothing, checked BOTH in the query and
      per-user before sending; NO deactivation happens at any threshold; inert
      without Mailgun.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.** Thresholds 7/14/28. Content names unseen likes and
      new matches — the reason to open it.
- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Commit.**

### Task 8: Promotional campaigns

**Files:**
- Create: `flame/jobs/promotionalEmailJob.js`
- Modify: `flame/models/User.js` (`promoCampaignsSent: [String]`)
- Test: `flame/__tests__/promotionalEmailJob.test.js`

**Interfaces:**
- Produces: `shouldSkipCampaign(sent, campaignId)`, `runPromotionalJob({now})`.

- [ ] **Step 1: Failing test** — `shouldSkipCampaign` as a pure table (no DB);
      a user who received the current campaignId is skipped; bumping the id
      re-sends; `promotions:false` receives nothing; sends go in batches of 50
      with a delay between them.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.** Copy BananaTalk's campaignId design AND its comment
      explaining why: repeat sends of identical content train Gmail to
      spam-fold. Batch 50 / delay 1s — a new sending domain has no reputation to
      spend.
- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Commit.**

### Task 9: Actually start the scheduler

**Files:**
- Modify: `flame/services/emailScheduler.js`, `flame/index.js`
- Test: `flame/__tests__/emailScheduler.test.js` (extend)

- [ ] **Step 1: Failing test** — the boot path calls `startEmailScheduler`; the
      placeholder no-op digest job is GONE; with Mailgun unset nothing is
      scheduled and no timer is left pending; `msUntil` keeps its existing
      contract.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.** Replace the placeholder with the two real jobs.
      Weekly digest is deliberately not one of them.
- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Commit.**

### Task 10: Settings manages every channel

**Files:**
- Modify: `lib/screens/settings/notification_settings_screen.dart`,
  `lib/models/notification_settings.dart`,
  `lib/services/notification_settings_service.dart`,
  `lib/providers/notification_settings_provider.dart`
- Modify: all 13 `lib/l10n/app_*.arb`
- Test: `test/screens/settings/notification_settings_screen_test.dart` (extend)

- [ ] **Step 1: Failing tests:**
      - two sections — Push and Email — via `SettingsSection` from Scope B,
        rather than the bare `SwitchListTile` + `Divider` the screen uses now
      - the push master toggle disables the push children (existing behaviour,
        keep it)
      - **the push master toggle does NOT disable the email switches.** Separate
        channels; a push toggle silently stopping your email is wrong
      - `promotions` renders as opt-in (off by default) and can be turned ON —
        without this the promotional job correctly sends to nobody
      - `reengagement` renders as opt-out (on by default)
      - a failed update shows the existing failure snackbar and reverts
      - the AppBar title is localized. It is currently
        `const Text('Notifications')` — hardcoded, in a screen Scope B was
        supposed to have covered
      - the screen renders at text scale 1.0 and 2.0, and in both themes
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement**, adding the new keys across 13 locales. Check for an
      existing key before adding any: `retry`, `commonCancel` and
      `chatLoadFailed` all already existed when the chat sweep went looking.
- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Commit.**

### Task 11: Verification

- [ ] **Step 1:** `flutter analyze` — 0 errors, 0 warnings.
- [ ] **Step 2:** `flutter test` — full suite.
- [ ] **Step 3:** Backend sweep by exit code, per suite, results written
      incrementally. Re-run any failure alone before believing it.
- [ ] **Step 4:** Grep for leftovers: the placeholder digest string, the three
      deleted preference fields, `Text('Notifications')`, any non-transactional
      template without an unsubscribe link.
- [ ] **Step 5:** Confirm the suite leaves no pending timers — `node --test`
      completing rather than hanging IS the assertion.
- [ ] **Step 6:** Report. State plainly that nothing has been sent to a real
      inbox, because Mailgun is unconfigured, and that no device walkthrough has
      happened.
