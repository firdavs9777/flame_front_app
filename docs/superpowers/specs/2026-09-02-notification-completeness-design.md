# Notification completeness — permission, delivery, and promotional campaigns

**Date:** 2026-09-02
**Status:** approved to execute
**Scope:** app (`flame_front_app`) + backend (`language_exchange_backend_application/flame`)

Push now works end to end on both platforms. This closes the three gaps that
remain: the app cannot see whether the OS will actually show a notification, a
tap that launches the app never navigates, and there is no promotional channel
on push at all.

Three phases. A is a bug fix and ships first because it is live breakage. B and
C are one feature split across the two repositories.

---

## Phase A — the app tells the truth about push

### A1. Cold-start taps are dropped (bug, introduced 2026-09-02)

`main()` calls `attachHandlers()` before `runApp()`, deliberately: FCM returns
the launch notification from `getInitialMessage()` exactly once, and reading it
after the first frame is too late. But `PushNavigator.go()` resolves
`navigatorKey.currentState`, which is null before any widget tree exists. It
returns false and the payload is discarded.

The effect is that tapping a notification while the app is dead — the most
common case there is — opens Flame and never opens the conversation.

The existing test asserts `go()` "reports false rather than throwing when no
navigator is mounted". That pinned the safety and mistook it for the behaviour.

**Fix.** `PushService` holds one pending payload. `_onTap` stores it when
`go()` returns false rather than dropping it. `flushPendingTap()` replays it,
called from the first authenticated frame, by which time the navigator exists.

**A tap that cannot be honoured is discarded, not deferred indefinitely.** If
the app is not authenticated when the flush runs, the payload is cleared. The
notification was addressed to whoever was signed in when it arrived; replaying
it after a different account signs in would show one person another person's
conversation. Sign-out clears it for the same reason.

### A2. The settings screen cannot see the OS

Nothing in `lib/` reads `getNotificationSettings()`. A user who declines the
system prompt — or grants it and later revokes it, which is ordinary — sees
"All notifications: ON" with three live switches writing happily to the server.
The server sends. The OS drops it.

This is the failure `env.dart` already names: *a control that promises
something the app cannot do is worse than no control*. The guard was built at
the build-flag level and never at the runtime-permission level.

On iOS it is worse. Denial means APNs issues no token, so `_awaitApnsToken()`
returns false and the device is never registered at all, while the screen shows
five confident switches.

**Fix.** A `PushPermission` wrapper over `getNotificationSettings()`, so the
widget never imports `firebase_messaging`. When the status is not `authorized`,
the screen shows a banner above the push section with an **Open settings**
action (`permission_handler.openAppSettings()`, already a dependency) and
renders the three push switches non-interactive.

The email section is untouched. It works regardless of push permission, and
gating it would repeat the same mistake pointing the other way.

### A3. No recovery inside a session

`registerDevice()` runs only on the auth transition. Someone who declines, then
enables notifications in system settings, gets nothing until the app is
relaunched.

**Fix.** The settings screen observes `AppLifecycleState.resumed`, re-reads
permission, and calls `registerDevice()` when it has flipped to authorized.

### A4. Redundant registration

`registerDevice()` POSTs on every auth transition even when the token is
unchanged. `PushService` caches the last successfully registered token and
skips the request when it matches. Correctness is unaffected — the backend
upserts by device id — so this is purely a saved round trip per launch.

---

## Phase B — promotional push, server side

### B1. Consent is per channel, and the existing rule already says how

`notificationSettings.promotions` and `reengagement` mean **email**. The model
documents the two channels as deliberately independent, and it also records
*why* the two categories differ from each other:

> Opt-IN for marketing, opt-OUT for the re-engagement ladder, which is about
> the account's own state rather than promotion.

Push gets its own pair of fields carrying the same distinction:

| Field | Default | Why |
|---|---|---|
| `promotionsPush` | **false** — opt-in | Marketing. A user who consented to marketing *email* did not consent to marketing *push*. One shared flag would enrol every email subscriber into a channel they never chose. |
| `reengagementPush` | **true** — opt-out | The inactivity ladder. About the account's own state, not promotion — the same reasoning the email field already carries. |

Both are push, so both also obey the `enabled` master switch. The gates are
`enabled !== false && promotionsPush === true` and
`enabled !== false && reengagementPush !== false`.

Four fields where there were two is the honest shape: two categories across two
channels, each independently controllable. The alternative — one flag per
category spanning both channels — cannot express "email me about offers but
don't interrupt my phone", which is the setting most people actually want.

### B2. Campaigns are records, not a recurring job

`emailScheduler.js` deliberately keeps promotions off the daily timer, with the
reason recorded: *"a campaign goes out when there is new content, triggered
deliberately, and putting marketing on a daily timer is the repeat-send problem
campaignId exists to prevent."*

That precedent holds. A campaign is a document:

```
PushCampaign {
  campaignId  String  unique   // dedup key, same role as the email job's
  title       String
  body        String
  route       String?          // an AppRoutes name, validated
  sendAt      Date?            // null = send on the next tick
  status      'scheduled' | 'sending' | 'sent' | 'cancelled'
  stats       { recipients, sent, skipped }
}
```

A scheduler tick every five minutes claims due campaigns
(`status: 'scheduled'`, `sendAt <= now`) and runs them. Claiming is a single
atomic `findOneAndUpdate` to `'sending'`, so two ticks — or two workers, and
the droplet runs two uvicorn-equivalent processes — cannot send one campaign
twice.

### B3. Delivery reuses what exists

`promotionalPushJob` is `promotionalEmailJob`'s shape with `sendEmail` swapped
for `pushService.sendToUser`: batches of 50 with a 1s pause, skip any user whose
`promotionalPushSent` already contains this `campaignId`, record the id on
success.

`pushService.sendPromotion(userId, {title, body, campaignId, route})` gates on
`promotionsPush` and delegates to `sendToUser`, matching `sendChatMessage` and
`sendNewMatch` exactly.

### B4. Re-engagement push

`inactivityEmailJob` already computes who has gone quiet, at which thresholds,
and de-duplicates with `reengagementSent`. The push ladder reuses that shape
rather than re-deriving it:

- Its own `reengagementPushSent` array, **not** the email one. Sharing would
  mean an email at day 3 silences the push at day 3, and one channel firing
  would silently consume the other's turn.
- Same thresholds, so the two channels stay conceptually aligned.
- Runs on the daily 09:00 tick beside the email job — the hour the scheduler
  already justifies: *"a re-engagement email that lands overnight is buried
  under everything that arrives before the recipient wakes up."* A push at 03:00
  is worse than buried; it wakes someone up.
- `pushService.sendReengagement(userId, {threshold})` gates on
  `reengagementPush` and delegates to `sendToUser`.

Its payload routes nowhere specific — it opens the app, which is the point.

### B5. Trigger

`POST /flamebackend/v1/admin/push-campaigns` (admin-guarded) creates a campaign;
`GET` lists; `DELETE /:campaignId` cancels one that has not started. Zod
validated, `route` checked against a whitelist so a campaign cannot deep-link
somewhere the app will not route.

---

## Phase C — promotional push, app side

- `NotificationSettings` gains `promotionsPush` (default false) and
  `reengagementPush` (default true), reading `promotions_push` /
  `reengagement_push` and emitting camelCase, each with a provider setter.
- The settings screen gains two switches in the **push** section, gated on
  `enabled` like the other two. They sit with push, not beside their email
  namesakes, because the channel is what they control — and having
  "Promotions" appear once under Push and once under Email is exactly the
  distinction users need to see rather than a duplication to collapse.
- `PushPayload` learns `type: 'promotion'` (carrying an optional `route`) and
  `type: 'reengagement'` (which routes nowhere and simply opens the app).
- Routing validates `route` against `AppRoutes.all` and falls back to no
  navigation when it is absent or unknown. A campaign authored against a route
  a future release removes must open the app, never a crash or a not-found.

---

## Testing

| Area | Pinned |
|---|---|
| Pending tap | queued when no navigator; replayed on flush; dropped when unauthenticated; cleared on sign-out |
| Permission | authorized / denied / provisional; banner presence; switches non-interactive when denied |
| Resume | re-register fires only on the denied→authorized transition |
| Token cache | second registration with an unchanged token sends no request |
| Payload | `promotion` and `reengagement` parse; unknown `route` yields no destination; every producible route is in `AppRoutes.all` |
| Re-engagement | its own sent-list, so an email at a threshold does not silence the push |
| Campaign claim | two concurrent ticks send once |
| Job | campaignId dedup; opt-out and master-switch skips |

Both suites must stay green (`flutter test`, `node --test`), `flutter analyze`
error-clean, and both platforms must build.

## Deliberately not built

- **`flutter_local_notifications`.** No in-app banners and no device-scheduled
  notifications. The socket already delivers foreground chat live, so a banner
  would announce what is on screen. Revisit only with a case the server cannot
  serve.
- **Campaign authoring UI.** The endpoint is the interface for now.
- **Localised campaign copy.** The server sends one title/body, in whatever
  language it was authored. Chat and match pushes already share this limitation;
  fixing it is one job across all three, not part of this one.
