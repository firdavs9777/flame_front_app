# Scope C — Notifications: push, and email that actually sends

**Date:** 2026-08-23
**Status:** approved (two decisions recorded below)
**Scope:** backend (`flame/`) + app

Third and last of the three scopes agreed for the pre-release push. A and B are
merged and live.

## Two phases, and why C2 goes first

**C1 — Push.** Blocked end-to-end on Firebase credentials (project,
`google-services.json`, `GoogleService-Info.plist`, an APNs key, and
`FLAME_FIREBASE_PROJECT_ID` on the droplet). Fully buildable behind the existing
seam, but cannot be verified to deliver.

**C2 — Email.** Needs only a flame Mailgun key and domain. `isConfigured()`
already gates every path, so it ships inert and starts working when the config
lands. Nothing about C2 waits on C1.

C2 first, because it can be finished rather than parked.

## What already exists, and what is a lie

`emailService`, `emailTemplates`, `sendEmail` and `emailScheduler` are all
written. Almost none of it runs:

- **`startEmailScheduler()` is never called.** The only reference to it in the
  entire repo is a comment in `flame.env.example`. It has never executed.
- **Its one job is a placeholder** that logs `email digest job tick
  (placeholder, no-op)` and reschedules itself. It sends nothing.
- **`sendPasswordChanged` is never called.** Template and function both ready.
- `sendWelcome` IS wired, on register, fire-and-forget. The one thing that works.

**Four dead fields in `notificationSettingsSchema`:** `newMatches`,
`newMessages`, `superLikes`, `promotions`. Nothing reads or writes any of them.
Only `enabled`, `chatMessages` and `matches` are live. Same drift as the three
interest catalogues in Scope A.

**And a switch that controls nothing:** the route accepts `matches`, the app
model carries it, the settings screen toggles it — but `pushService` only checks
`chatMessages`, because match push does not exist. A user can turn off
notifications they were never receiving.

## Decisions taken

**No deactivation.** BananaTalk's inactivity ladder ends in account
deactivation. flame's will not. Deactivating dating profiles needs an
account-state machine, a reactivation path, and a decision about whether matches
and conversations survive — and it risks closing paying users' accounts. That is
its own scope, if ever. flame sends re-engagement email and stops.

**Emails in scope:** password-changed (wire the existing one), inactivity
re-engagement, and promotional. Weekly digest is explicitly out; the scheduler's
placeholder is replaced by the inactivity job instead.

## Localization

**flame's `User` has no locale field**, and the templates are hardcoded English
HTML. The app ships 13 locales, so the user base is not English-first and the
server currently cannot know what language to write in.

- Add `locale` to the flame `User` (default `en`).
- The app sends it: at registration, and whenever the language screen changes it.
- Copy moves to `flame/email_templates/{locale}.json`, keyed per template, with
  per-key fallback to `en` — mirroring BananaTalk's catalogs so a missing string
  degrades to English rather than to nothing.

## C2 design

### 1. Unsubscribe — the gate on everything non-transactional

No unsubscribe route exists. Sending promotional or re-engagement mail without
one-click unsubscribe violates CAN-SPAM, and GDPR requires both consent and a way
to withdraw it. This is not polish; it gates the other jobs.

- `GET /email/unsubscribe?u=<userId>&c=<category>&s=<signature>` — **public**,
  no login. The signature IS the authentication: HMAC-SHA256 over `u|c` with a
  server secret. One click, no confirmation step, per CAN-SPAM.
- Categories: `promotions`, `reengagement`. Transactional mail (welcome,
  password-changed) has no unsubscribe and must not offer one.
- Also emit a `List-Unsubscribe` header, which is what Gmail and Apple Mail
  surface as their own one-click control.
- Flipping the matching preference to false is the whole action.
- A tampered or unknown signature returns the same page as success. Telling a
  prober which user ids exist is worse than a useless click.

### 2. Preferences that mean something

- Delete `newMatches`, `newMessages`, `superLikes` — duplicates of live fields.
- Keep `promotions`, and WIRE it: default `false` is correct opt-in behaviour,
  and it is what unsubscribe writes to.
- Add `reengagement` (default `true` — it is a service email about the account,
  not marketing, so opt-out rather than opt-in).
- Every job checks its preference twice: in the query, and per-user before
  sending. BananaTalk does both, because the query alone races against a
  preference changed mid-run.

### 3. Inactivity re-engagement

Ladder at 7, 14 and 28 days on the existing `lastActive`. One send per
threshold per user, ever — recorded on the user, or a user crossing 7 days
twice gets the same mail twice.

Content is the reason to open it: unseen likes and new matches since they left,
which the app already tracks.

### 4. Promotional campaigns

Copy BananaTalk's `campaignId` design exactly, including the reason:

> bump this to a new value whenever the content changes so the campaign goes out
> to everyone again. Users who already received the CURRENT campaignId are
> skipped — this stops the identical-weekly-promo hammer that trains Gmail to
> spam-fold repeat sends of the same content.

- `promoCampaignsSent: [String]` on the User.
- `shouldSkipCampaign(sent, campaignId)` as a pure function, unit-testable
  without a database.
- Batches of 50 with a 1s delay, as BananaTalk does. A brand-new sending domain
  has no reputation, and a burst is the fastest way to lose it before it exists.

### 5. Start the scheduler

`startEmailScheduler()` gets called from the flame boot path, and its placeholder
becomes the real jobs. It must stay inert without Mailgun config — the current
`isConfigured()` guard already does this, and the tests depend on it (a pending
`setTimeout` would hang the suite).

Jobs are pure functions over an injected clock wherever possible: `msUntil` is
already written that way and is the model to follow.

## C1 design

### 6. The app half of push

`firebase_messaging` is not a dependency; there is no push code in the app at
all. But the seam is ready: `auth_service` already accepts `deviceToken` and
sends `device_token` on login, register and both social paths — four parameters
no caller has ever supplied.

- Permission request, at a moment the user understands rather than at cold start.
- Token retrieval, registration through `/notifications/register-token`, and
  refresh handling.
- Foreground, background and terminated handlers.
- Tap → deep link, using `appNavigatorKey`, `AppRoutes.chat` and
  `ChatRouteArgs.id`. This is why navigation went first, and it is already built
  and tested.

### 7. The two events that do not push

Only chat messages send push. A new match and a new like — the two things that
actually bring people back to a dating app — send nothing. Wire both, and fix
the `matches` toggle so it controls the thing it names.

### 8. Bundling

Copy `notificationBundlingService`'s `collect`/`flush` over a bucket key. Without
it, five likes in a minute is five pushes, which is how an app gets its
notifications switched off entirely.

## Testing

- `msUntil` and `shouldSkipCampaign` are pure: table-driven, no database.
- Unsubscribe: valid signature flips the preference; tampered signature does not,
  and is indistinguishable in the response; a transactional template carries no
  unsubscribe link.
- Each job: honours its preference in query AND per-user; never sends the same
  threshold or campaign twice; inert without Mailgun.
- Locale: a user with `ko` gets Korean; a missing key falls back to English per
  key rather than dropping the whole template.
- Push: the two new events fire, respect their preferences, and bundle.
- App: a tap resolves to the right conversation, including from a cold start.

## Risks

**A brand-new sending domain has no reputation.** Sending marketing before any
transactional volume is the fastest way to get spam-foldered permanently. Ship
password-changed and re-engagement first, promotional after there is a sending
history. Flagged because the decision to include promotional was explicit and
this is the one thing that can make it counterproductive rather than merely
ineffective.

**Consent for promotional mail has no UI.** `promotions` defaults to false, which
is correct — but nothing in the app lets a user turn it ON. Without that, the
job correctly sends to nobody. An email-preferences section is therefore part of
C2, not a follow-up.
