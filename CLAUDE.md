# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

DeepRead: an RSS reader that works fully offline, including articles from JavaScript-heavy sites a
traditional feed parser can't handle. A backend worker headlessly renders each article once
(Playwright + Readability.js), and the Flutter client downloads the pre-packaged static result for
offline reading. The render is a **shared cache**: `feeds` and `articles` are global tables — one
render serves every subscriber of that feed, not just the user who added it.

- `mobile/` — Flutter client (Android/iOS)
- `backend/` — Python worker: polls RSS feeds and renders JS-heavy pages into offline-ready packages
- `supabase/` — Postgres schema + RLS policies + storage bucket config

See [TODO.md](TODO.md) for deferred features and known-missing MVP pieces (with exact file/line
pointers), and [TECH_DEBT.md](TECH_DEBT.md) for accepted architectural trade-offs. Check both before
assuming something is a bug rather than a known gap.

## Commands

Fill in `backend/.env` and `mobile/.env` (copy from the `.example` files) with Supabase project
URL + keys first.

```
make backend-venv   # one-time: creates backend/.venv, installs deps + chromium
make backend-test   # cd backend && . .venv/bin/activate && python -m pytest
make backend-run    # runs the poller/renderer worker locally
make backend-render-url URL=<url>  # render one real URL through the pipeline, no Supabase needed —
                                    # for debugging site-specific render failures locally

make mobile-test        # cd mobile && flutter test
make mobile-analyze     # cd mobile && flutter analyze
make mobile-run                  # flutter run on a connected device (DEVICE=<id> to target one)
make mobile-install DEVICE=<id>  # build debug APK + adb install onto a specific device
```

Run a single backend test: `cd backend && . .venv/bin/activate && python -m pytest tests/test_paywall.py -k detects_redirect`

Run a single mobile test: `cd mobile && flutter test test/widget_test.dart`

**Always use the `mobile-*` Make targets (or pass `$(DART_DEFINES)` manually) instead of calling
`flutter run`/`flutter build` directly** — they inject `SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY` as
`--dart-define`s from `mobile/.env`. Without them the app builds silently but can't reach Supabase.

Backend deploy (Fly.io, app `deepread-worker`, org `deepread`): `make backend-deploy` /
`make backend-logs`. No HTTP service is exposed — it's a pure background poller/renderer. Fly's
default 2-machine primary+standby setup means only one instance is ever actively polling/rendering;
see TECH_DEBT.md's "stuck `rendering` rows" note for what that assumption depends on if that changes.

## Backend architecture (`backend/deepread_worker/`)

Two independent asyncio loops started from `main.py`, sharing one Supabase service-role client
(`db.py` — bypasses RLS, since the worker is the only writer to `feeds`/`articles`):

- **Poller loop** (`poller.py`, every `poll_interval_seconds`): fetches each due feed's XML, diffs
  entries against `articles.canonical_url`, inserts new rows as `status='pending'`.
- **Renderer loop** (`renderer.py`, every 10s): claims `pending` articles up to
  `render_concurrency`, renders each with Playwright + Readability, sanitizes and zips the result
  (`packaging.py`), uploads to Supabase Storage, marks `ready`.

`articles.status` (`pending` → `rendering` → `ready`/`failed`) is an **implicit job queue** — no
Redis/dedicated queue exists (see TECH_DEBT.md). The `pending`→`rendering` transition in
`_render_one` is a conditional update (`.eq("status", "pending")`) used as an optimistic lock so
two worker replicas can't double-render the same article; a crash mid-render leaves a row stuck in
`rendering` until `cleanup.py`'s stale-claim sweep reclaims it (gated by the `claimed_at` column
and `stale_claim_minutes`, not by a settings on/off flag — see TECH_DEBT.md).

Per-article render pipeline in `_render_one`:
1. `robots.py` — check the target host's robots.txt (cached in-process via `lru_cache` per host)
2. Playwright renders the page (`networkidle`, falling back to `domcontentloaded` + fixed wait if
   that times out — a known heuristic limitation, not a bug to "fix" casually)
3. `paywall.py` — best-effort paywall detection; deliberately conservative (false positives —
   skipping a public page — are cheap; false negatives — caching login-gated content — are not,
   see the legal-risk note in TECH_DEBT.md). Paywalled articles keep `storage_path=null` and are
   marked `ready` with only the RSS-provided `summary` for offline display.
4. `packaging.py` — Readability extraction → `nh3` sanitize (strict tag/attribute allow-list) →
   download referenced images → zip as `index.html` + `images/`. The embedded `_ARTICLE_CSS`
   intentionally matches `mobile/lib/theme/app_theme.dart`'s dark theme, since the zip is rendered
   raw in a client WebView with no app chrome around it.
5. Upload to Storage bucket `articles` at `{article_id}.zip`; flip status to `ready`.

Failures anywhere in that pipeline retry up to `render_max_retries` (via `retry_count`) before
`status='failed'`.

## Mobile architecture (`mobile/lib/`)

- `data/local/database.dart` — `drift` (SQLite) schema: `LocalFeeds` + `LocalArticles`. This is a
  **partial, offline-first cache**, not a mirror of the remote schema — `LocalArticles` only holds
  articles actually downloaded onto this device, and columns exist only as needed for offline
  display (e.g. no `LocalArticles.summary` yet, which is why paywalled articles can't sync — see
  TODO.md).
- `data/remote/` — direct Supabase/PostgREST calls (`supabase_client.dart` wraps init; no other
  abstraction layer over the Supabase SDK). RLS policies (`supabase/migrations/0001_init.sql`) are
  the real access boundary, not client-side logic — e.g. `articles` select is scoped server-side to
  the user's subscribed feeds via `user_feed_subscriptions`.
- `features/sync/sync_service.dart` — the only thing that moves data from Supabase into the local
  DB: refreshes subscribed feeds, then downloads+unzips any `status='ready'` article not already
  present locally. Deliberately dumb (no pagination/watermark/per-article error isolation yet — see
  TODO.md) since all real rendering work already happened server-side.
- `features/sync/background_sync.dart` — `workmanager` periodic task. Runs in a **separate isolate**
  with no access to the running app's memory, so it re-initializes Supabase and opens its own
  `AppDatabase` from scratch. iOS's native BGTaskScheduler setup (`Info.plist` keys and
  `AppDelegate.swift` registration) is now wired up (unverified on real hardware — see
  TECH_DEBT.md); the try/catch around
  `BackgroundSync.register()` in `main.dart` still exists and still matters for *other* causes of
  registration failure (e.g. a future OS-level restriction), not for the missing-config gap it
  used to be covering for.
- `features/auth/auth_gate.dart` — Supabase auth session is the single source of truth for
  logged-in state (`StreamBuilder` over `onAuthStateChange`); no separate local auth flag.
- Plain `StatefulWidget`/`setState` throughout — `riverpod` is a listed dependency but currently
  unused; don't reach for it without checking TECH_DEBT.md's note on when to actually adopt it.

**Testing drift-backed widgets:** subscribing to a live `drift` `.watch()` stream inside a
`testWidgets` fake-async zone hangs indefinitely (confirmed, not a flake). The established
workaround — follow it for any new screen backed by a `.watch()` query — is to have the widget take
an injectable `Stream` parameter that defaults to the live query, so widget tests can pass
`Stream.value(...)` instead of touching drift. See `FeedListScreen` for the pattern.

## Branching & releases

Gitflow: `develop` is the default branch and integration point for everyday work; `main` only
moves via `release/*` or `hotfix/*` merges and always reflects what's actually deployed.

- **`feature/*`** — branch from `develop`, PR back into `develop`.
- **`release/X.Y.Z`** — branch from `develop` when cutting a release; PR into `main`. Merging that
  PR triggers `.github/workflows/release.yml`, which tags `vX.Y.Z` (version taken from the branch
  name), publishes a GitHub Release, runs `flyctl deploy --app deepread-worker`, builds and
  attaches a `flutter build apk --release` artifact (still debug-signed — see TODO.md), and opens
  an automated `main` → `develop` sync PR.
- **`hotfix/X.Y.Z`** — same as `release/*` but branched from `main` for urgent fixes; goes through
  the same workflow and back-merge.
- `.github/workflows/ci.yml` runs backend `pytest` and mobile `flutter analyze`/`flutter test` on
  every PR into `develop` or `main`, and both branches require it to pass (no required review
  count — solo-maintainer repo, and GitHub disallows self-approval anyway). It also runs on every
  `push` to `develop` (i.e. again right after a PR merges) — that's not redundant, it's what warms
  the Actions cache at the default-branch scope so the *next* PR's first run can restore from it
  instead of starting fully cold (PR-scoped caches live under `refs/pull/N/merge` and can't be
  reused by other PRs; only a default-branch — or same/base-branch — cache can). Not added on
  `main` too: GitHub Actions cache lookups already fall back to the repo's default branch
  (`develop`) from anywhere, including `release/*`/`hotfix/*` PRs targeting `main`, so a
  `main`-scoped cache would be redundant — and would only add pressure on the repo's Actions cache
  quota, which is already near/over the 10GB eviction cap (see TECH_DEBT.md).

## Supabase (`supabase/migrations/`)

Plain SQL migrations applied in order, no CLI migration tooling wired up — see
`supabase/README.md` for the paste-into-SQL-Editor workflow. `feeds`/`articles`/`takedown_requests`
are global/shared tables gated by RLS policies scoped through `user_feed_subscriptions`; the worker
connects with the service-role key and bypasses RLS entirely (intentional — it's the only writer).
When changing schema, add a new `NNNN_description.sql` file rather than editing an applied one.
