# DeepRead

An RSS reader that works fully offline — including articles from JavaScript-heavy sites that a traditional feed parser can't handle. A backend worker headlessly renders each article once (Playwright + Readability.js), and the Flutter client downloads the pre-packaged static result for offline reading.

See [TODO.md](TODO.md) for deferred features and open product decisions, and [TECH_DEBT.md](TECH_DEBT.md) for known architectural limitations.

## Structure

- `mobile/` — Flutter client (Android/iOS)
- `backend/` — Python worker: polls RSS feeds and renders JS-heavy pages into offline-ready packages
- `supabase/` — Postgres schema + RLS policies + storage bucket config

## Quickest path: `make`

Fill in `backend/.env` (copy from `backend/.env.example`) and `mobile/.env` (copy from `mobile/.env.example`) with your Supabase project's URL + keys, then:

```
make backend-venv   # one-time: creates backend/.venv, installs deps + chromium
make backend-test
make backend-run     # runs the poller/renderer worker

make mobile-test
make mobile-run                  # flutter run on a connected device
make mobile-install DEVICE=<id>  # or: build + adb install onto a specific device
```

The `mobile-*` targets read `SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY` out of `mobile/.env` and pass them as `--dart-define`s automatically — see `make help` for the full list of targets. This exists because it's easy to forget those flags running `flutter run`/`flutter build` directly, which silently produces an app that can't reach Supabase.

## Manual setup (without `make`)

**Backend:**
```
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
playwright install chromium
cp .env.example .env  # fill in your Supabase project URL + service role key
python -m pytest
python -m deepread_worker.main
```

**Mobile:**
```
cd mobile
flutter pub get
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

## Supabase setup

Apply `supabase/migrations/` in order (paste into the dashboard's SQL Editor, or use the CLI) — see `supabase/README.md` for details.

## Backend deployment

The worker runs on Fly.io as app `deepread-worker` (org `deepread`), configured via `backend/fly.toml` — no HTTP service is exposed since it's a pure background poller/renderer. Fly's default 2-machine setup gives us a primary + a standby that only takes over on host hardware failure (not for load-balancing), which conveniently means only one instance is ever actively polling/rendering — see the "Stuck `rendering` rows" note in TECH_DEBT.md for what that assumption depends on if this ever changes (the render claim's optimistic lock only has to defend against crash recovery, not a true concurrent claimer).

```
make backend-deploy   # flyctl deploy --app deepread-worker
make backend-logs     # tail production logs
```

Secrets (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`) are already set on the app via `flyctl secrets set`; update them with the same command if they ever change (e.g. after a key rotation).
