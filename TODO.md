# TODO

MVP scope (auth screens, sync service, add-feed wiring, and iOS background sync config) is now
fully built. Everything below is deferred/out-of-scope for the MVP, not missing MVP work.

## Features

- [ ] Feed auto-discovery + OPML import (MVP is paste-URL only)
- [ ] Push notifications (FCM/APNs) to trigger faster sync (MVP polls on open + background fetch only)
- [ ] Starring/favoriting articles
- [ ] Folders/tags for feeds
- [ ] Full-text search across downloaded articles (SQLite FTS5)
- [ ] Desktop platform support (Linux/macOS/Windows) — MVP is Android + iOS only
- [ ] Cross-device sync of read/starred state — currently local-only per device
- [ ] User-settable feed names. Feeds currently show their raw URL as the display name (`feed.title ?? feed.url` in `FeedListScreen`, and `feeds.title` is never actually populated server-side) — let the user rename a feed to something readable.
- [ ] Delete an Article on local device. (need to then make sure it doesn't get re downloaded
- [ ] Combined "all articles" view across every subscribed feed, so the user doesn't have to open each feed individually to see what's new.
- [ ] "Last synced" timestamp shown in the UI (e.g. next to the sync button in `FeedListScreen`) — currently sync happens with no visible indication of when it last ran or succeeded.
- [ ] Settings page — a home for sign-out (currently just an app bar icon), last-synced info, and future preferences (theme, retention, etc.) rather than piling everything into the feed list app bar.
- [ ] Link to the app's GitHub repo somewhere in the app (e.g. settings page once it exists).
- [ ] **Prompt the user to exempt DeepRead from OEM battery restrictions.** Blocked on the Settings page above existing — this belongs there rather than as a one-off dialog/banner bolted onto `FeedListScreen`. Confirmed on a Samsung device (One UI, Android 16) that `BackgroundSync`'s periodic WorkManager task can sit enqueued indefinitely (`run_attempt_count=0` in WorkManager's own `workdb`) because the OS applies a manufacturer-specific network block (`REASON_OEM_DENY` in `dumpsys jobscheduler`'s `ConnectivityController`) independent of Doze, App Standby, Data Saver, and Battery Saver — none of which the app can detect or work around in code. This isn't in Samsung's "Sleeping apps" list either, just the default "Optimised" per-app battery mode. Once the Settings page exists, it should guide the user to set Battery mode to "Unrestricted" for DeepRead (`Settings > Apps > DeepRead > Battery`), otherwise background sync silently never runs on affected devices.
- [ ] Audio Reader - can we make use of iOS and Android native TTS
- [ ] Link to the original article's live URL from the reader screen, so the user can open it in a real browser when online (useful when the offline render is imperfect, e.g. the Readability edge cases noted in TECH_DEBT.md).

## Storage & scaling

- [ ] Per-feed article-count cap — the server-side retention policy (`deepread_worker.cleanup`) is age-based TTL only; a per-feed cap was deferred to avoid PostgREST group-by/window-function complexity. Revisit if a single high-volume feed blows past what age-based expiry alone bounds.
- [ ] Per-user rate limiting/quotas on feed adds — MVP has no cost-abuse protection beyond basic sanity limits
- [ ] Admin/observability view for failed renders & dead-lettered articles
- [ ] Split poller/renderer into separate services with a real queue (Redis) once usage justifies it — MVP uses a single worker process with `articles.status` as an implicit queue

## Tooling

- [ ] PR-time migration validation against a shadow/staging Supabase project (e.g. `supabase db diff`/`db push --dry-run` in `ci.yml`) — deliberately deferred when migrations were automated in `release.yml`, since it needs a second Supabase project that doesn't exist yet.
- [ ] **`backend/` has no dependency lock file.** `pyproject.toml` only specifies version ranges (`playwright>=1.48`, etc.) and `make backend-venv`/the Dockerfile both resolve fresh via `pip install -e ".[dev]"` — so a transitive dependency bump upstream can change what actually ships to prod (`make backend-deploy`) with no corresponding commit in this repo, and there's no way to reproduce exactly what was deployed on a given date. Worth adding `uv` + a committed `uv.lock`, with the Dockerfile/Makefile switched to `uv sync`.
- [ ] **Revisit the `workmanager` pin + `dependency_overrides` in `mobile/pubspec.yaml` once Flutter 3.47 is stable.** Pinned because `workmanager_android` needs AGP 9's built-in Kotlin, but this project's `android/gradle.properties` sets `android.builtInKotlin=false` (Flutter's own template default). Flipping that flag to `true` doesn't work yet either — Flutter's plugin loader force-applies the legacy `kotlin-android` plugin to any subproject that doesn't self-declare KGP (e.g. `app_links`, pulled in via `supabase_flutter`), which collides with AGP 9's built-in compiler. That's a known Flutter bug ([flutter/flutter#189133](https://github.com/flutter/flutter/issues/189133), fixed by #188543) that only ships starting Flutter 3.47 — beta only as of writing, not yet in stable. Once on 3.47+, try flipping `android.builtInKotlin=true` (and dropping `android.newDsl=false`) and unpinning `workmanager`/removing the three `workmanager_*` overrides in one go.

## Business

- [ ] **Monetization/billing model — explicitly undecided.** No billing infra exists yet; this needs a product decision before it's designed, not an engineering default.


## Release

- [ ] **Launch on the Play Store.** the usual store-listing work: screenshots, privacy policy URL, data safety questionnaire, content rating, and a closed testing track before production.

