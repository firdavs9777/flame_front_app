# Flame

Flutter dating app. This repo is the **client only**.

## The backend

**`/Users/davis/Desktop/Personal/language_exchange_backend_application`** — specifically the
`flame/` directory inside it.

- Node/Express (`bananatalk_api`), MongoDB via Mongoose, `sharp` for images.
- `server.js:366` mounts `flameRouter` at `/flamebackend/v1`.
- Live at `https://api.banatalk.com/flamebackend/v1` (64.23.181.246), which is what
  `lib/config/env.dart:150` points at.
- Flame's own code lives in `flame/{routes,controllers,services,models,socket,jobs}`.
  The rest of that repo is BanaTalk, a different product sharing the host.

## Do NOT use `flame_backend`

`/Users/davis/Desktop/Personal/flame_backend` is a **FastAPI/Python implementation that is
not deployed and never has been.** Its name matches this project, which is exactly why it
is a trap.

Evidence, so nobody re-litigates it:

- Its EC2 host (15.165.66.89) refuses SSH; its deploy workflow has failed on every run.
- `api.flame.banatalk.com` (that host) does not respond.
- Its own history contains "Revert the marketing endpoint — wrong codebase".

**Tell for which backend you are reading:** the real one validates with **zod**
(`z.object`, `z.string().min(8)`). If you are looking at Pydantic or FastAPI, you are in
the wrong repository. Specs in `docs/superpowers/specs/` quote zod schemas — that is the
live server.

## Conventions

- Specs: `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
- Plans: `docs/superpowers/plans/YYYY-MM-DD-<topic>.md`
- Tests: `flutter test` (143 files). `flutter analyze` must be error-clean.
- `test/config/app_version_test.dart` fails the build if `pubspec.yaml` and
  `lib/config/app_version.dart` disagree — bump both together.
