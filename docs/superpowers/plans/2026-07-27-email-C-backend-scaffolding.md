# Email (C) — Backend Scaffolding (infra-graceful)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Checkbox steps.

**Goal:** Build the flame email capability so it's wired + tested but **degrades gracefully when Mailgun isn't configured**: a guarded `sendEmail` primitive, pure HTML/text templates, an `emailService` with a couple of transactional senders, a welcome-email trigger on registration, and an `emailScheduler` module (for future scheduled/digest sends). Modeled on BananaTalk's `utils/sendEmail.js` / `services/emailService.js` / `jobs/scheduler.js`. Actual delivery only happens once the user provides Mailgun creds; until then every send is a logged no-op.

## Global Constraints
- Repo `/Users/firdavsmutalipov/Projects/BananaTalk/backend`, branch **`feat/flame-chat`** (never `main`). ISOLATION unchanged (flame-only files). Re-check branch before commits.
- `mailgun.js` + `form-data` are already in the shared backend deps (`require` works from `flame/`). Do NOT add creds.
- **Graceful gating:** email is "configured" iff `process.env.MAILGUN_API_KEY` AND `process.env.MAILGUN_DOMAIN` are set. When not configured, `sendEmail` logs + returns `{skipped:true}`, never throws. Tests run with NO creds → exercise the no-op + template-building paths.
- Flame conventions; `node --test` (don't background). Reference: BananaTalk `utils/sendEmail.js`, `services/emailService.js`, `utils/emailTemplates.js`, `jobs/scheduler.js`; flame patterns.
- Do NOT wire the scheduler into the shared `server.js` boot in this pass (a dormant scheduler needn't touch the shared server) — that's a documented one-line guarded go-live step.

---

### Task 1: sendEmail primitive + templates + emailService + tests
**Files:** create `flame/utils/sendEmail.js`, `flame/utils/emailTemplates.js`, `flame/services/emailService.js`; test `flame/__tests__/email.test.js`.
- `sendEmail.js`: `isConfigured()` (MAILGUN_API_KEY && MAILGUN_DOMAIN). `sendEmail({to, subject, html, text})` — if `!isConfigured()` → `logger.info('email not configured, skipping')` + return `{skipped:true}` (NO throw). Else build the mailgun.js client (region eu/us from `MAILGUN_REGION`), `from` = `${FROM_NAME} <${FROM_EMAIL}>`, `mg.messages.create(MAILGUN_DOMAIN, {...})`; on error log + return `{sent:false, error}` (never throw into the caller). Export both.
- `emailTemplates.js`: pure builders returning `{subject, html, text}` — `welcome({name})`, `passwordChanged({name})`. No I/O. Deterministic.
- `emailService.js`: `sendWelcome(user)` → builds `templates.welcome` + `sendEmail`; `sendPasswordChanged(user)` similarly. Respect a minimal guard (skip if no `user.email`). Return the sendEmail result.
- Tests (`email.test.js`, no Mailgun): `isConfigured()` false when env unset; `sendEmail(...)` returns `{skipped:true}` + does NOT throw; `emailTemplates.welcome({name:'Ann'})` returns subject/html/text containing 'Ann' (pure assertion); `emailService.sendWelcome({email:'a@x.com',name:'Ann'})` returns skipped (unconfigured) without throwing; `sendWelcome({name:'Ann'})` with no email → skipped, no throw.
- Commit `feat(flame): guarded email primitive + templates + emailService (no-op until Mailgun configured)`.

### Task 2: emailScheduler module + welcome trigger on register + tests
**Files:** create `flame/services/emailScheduler.js`; modify `flame/controllers/authController.js` (or authService) to fire a best-effort welcome email on successful register; test `flame/__tests__/emailScheduler.test.js`.
- `emailScheduler.js`: pure helper `msUntil(hour, minute, now=new Date())` → milliseconds until the next occurrence of that local time (return >0, <=24h). `startEmailScheduler()` — if `!sendEmail.isConfigured()` → log + return without scheduling any timers (fully inert when unconfigured). When configured, schedule recursive-setTimeout jobs (structure only; a placeholder digest job is fine — it can be a no-op body for now). Export `msUntil` + `startEmailScheduler`. (NOT wired into server.js here.)
- Register trigger: in the register flow (authController/authService), after the user is created + tokens issued, add a guarded best-effort `require('../services/emailService').sendWelcome(user).catch(()=>{})` (or try/catch) — must NEVER fail or delay registration. Find the exact register success point; keep it fire-and-forget + guarded.
- Tests (`emailScheduler.test.js`): `msUntil` returns a positive value <= 24h for a few (hour,minute,now) cases (pure, deterministic — pass `now` in); `startEmailScheduler()` with email unconfigured returns without throwing and schedules nothing (assert it doesn't hang the test / no pending timers — since it should early-return). Do NOT test real scheduled delivery.
- Verify the register trigger didn't break auth: `node --test flame/__tests__/auth.test.js` (or authService.test.js) still green.
- Commit `feat(flame): email scheduler module + welcome email on register (guarded)`.

### Task 3: verification
- `node --test flame/__tests__/email.test.js flame/__tests__/emailScheduler.test.js flame/__tests__/auth.test.js flame/__tests__/authService.test.js` green; branch feat/flame-chat; clean tree.

## Deferred (needs the user's Mailgun infra)
- Real delivery (Mailgun account + verified domain DNS + MAILGUN_* env on the server).
- Wiring `startEmailScheduler(io?)` into `server.js` boot (one guarded line, at go-live).
- The full BananaTalk sender catalog (digests, inactivity, admin reports) + localized template catalogs.

## Self-Review
Everything here runs + is tested WITHOUT Mailgun (no-op + pure-template + msUntil paths are the CI paths); real delivery is a guarded seam. Templates are pure/deterministic. Register trigger is fire-and-forget + guarded (can't break auth). Scheduler is inert until configured; not wired into the shared server. Isolation preserved. ✅
