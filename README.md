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
