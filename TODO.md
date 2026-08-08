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
- [ ] User-settable feed names (per-user override). `feeds.title` is now populated from the feed's own RSS/Atom `<title>` at poll time (`deepread_worker.poller._feed_title`), so `feed.title ?? feed.url` in `FeedListScreen`/`ArticleListTile`/etc. shows the feed's real name in the common case instead of falling back to the raw URL. What's still missing is a **per-user** rename — letting one subscriber call a feed something different from its RSS-provided name, without affecting other subscribers of the same shared `feeds` row. That needs its own storage scoped to `user_feed_subscriptions` (not `feeds`, which is global) plus display-priority logic (override → RSS title → URL). See `docs/superpowers/specs/2026-08-06-feed-display-names-design.md` for why the two are split.
- [ ] Per-article delete UI on local device. Bulk clear-all (Settings' "Clear downloaded articles") and automatic eviction (auto-expire read articles, per-feed cap — both in `RetentionService`, see TECH_DEBT.md's note on their off-by-default settings) already exist. An evicted article is unlikely to get silently re-downloaded either — `_evict` clears `localPath` but leaves `renderedAt` set, and `decideArticleSyncAction` skips re-downloading unless the backend's `rendered_at` is newer — but that's an incidental side effect of `renderedAt` surviving eviction, not a designed check (the `evicted` column itself is never read anywhere in `sync_service.dart`), and it stops holding the moment the source article gets re-rendered. What's missing is a way to evict a single article from its own list/reader view.
- [ ] **Prompt the user to exempt DeepRead from OEM battery restrictions.** The Settings page now exists (`mobile/lib/features/settings/settings_screen.dart`) and carries a generic static caption under the sync-frequency control ("If background sync never seems to run, check this app's battery settings — some manufacturers block background work regardless of this setting"), but that's not the guided prompt this item asks for. Confirmed on a Samsung device (One UI, Android 16) that `BackgroundSync`'s periodic WorkManager task can sit enqueued indefinitely (`run_attempt_count=0` in WorkManager's own `workdb`) because the OS applies a manufacturer-specific network block (`REASON_OEM_DENY` in `dumpsys jobscheduler`'s `ConnectivityController`) independent of Doze, App Standby, Data Saver, and Battery Saver — none of which the app can detect or work around in code. This isn't in Samsung's "Sleeping apps" list either, just the default "Optimised" per-app battery mode. The Settings page should guide the user to set Battery mode to "Unrestricted" for DeepRead (`Settings > Apps > DeepRead > Battery`), otherwise background sync silently never runs on affected devices.
- [ ] Audio Reader - can we make use of iOS and Android native TTS
- [ ] Link to the original article's live URL from the reader screen, so the user can open it in a real browser when online (useful when the offline render is imperfect, e.g. the Readability edge cases noted in TECH_DEBT.md).

## Storage & scaling

- [ ] Per-feed article-count cap on the **server-side shared cache** — `deepread_worker.cleanup`'s retention policy is still age-based TTL only; a per-feed cap was deferred to avoid PostgREST group-by/window-function complexity. Revisit if a single high-volume feed blows past what age-based expiry alone bounds. (Not to be confused with the per-feed cap already shipped in Settings — that one only evicts a device's own local downloads and does nothing to bound the shared `articles`/Storage bucket.)
- [ ] Per-user rate limiting/quotas on feed adds — MVP has no cost-abuse protection beyond basic sanity limits
- [ ] Admin/observability view for failed renders & dead-lettered articles
- [ ] Split poller/renderer into separate services with a real queue (Redis) once usage justifies it — MVP uses a single worker process with `articles.status` as an implicit queue

## Tooling

- [ ] PR-time migration validation against a shadow/staging Supabase project (e.g. `supabase db diff`/`db push --dry-run` in `ci.yml`) — deliberately deferred when migrations were automated in `release.yml`, since it needs a second Supabase project that doesn't exist yet.
- [ ] **`backend/` has no dependency lock file.** `pyproject.toml` only specifies version ranges (`playwright>=1.48`, etc.) and `make backend-venv`/the Dockerfile both resolve fresh via `pip install -e ".[dev]"` — so a transitive dependency bump upstream can change what actually ships to prod (`make backend-deploy`) with no corresponding commit in this repo, and there's no way to reproduce exactly what was deployed on a given date. Worth adding `uv` + a committed `uv.lock`, with the Dockerfile/Makefile switched to `uv sync`.
- [ ] **`workmanager_android` still self-applies the legacy `kotlin-android` Gradle plugin (KGP), which Flutter's build now warns about.** Upgrading `workmanager` to 0.10.7 (unpinning the `workmanager`/`workmanager_*` overrides that used to work around an older AGP-9 incompatibility — see git history) dropped that incompatibility, but `flutter build apk` still prints "Future versions of Flutter will fail to build if your app uses plugins that apply KGP" because `workmanager_android` hasn't migrated to Flutter's built-in-Kotlin plugin model yet. Revisit when a `workmanager_android` release adopts built-in Kotlin, or Flutter's warning becomes a hard failure, whichever comes first.
- [ ] **Flip `android.builtInKotlin=true` (and drop `android.newDsl=false`) once Flutter 3.47 is stable.** Blocked today because Flutter's plugin loader force-applies the legacy `kotlin-android` plugin to any subproject that doesn't self-declare KGP (e.g. `app_links`, pulled in via `supabase_flutter`), which collides with AGP 9's built-in compiler. That's a known Flutter bug ([flutter/flutter#189133](https://github.com/flutter/flutter/issues/189133), fixed by #188543) that only ships starting Flutter 3.47 — beta only as of writing, not yet in stable.

## Business

- [ ] **Monetization/billing model — explicitly undecided.** No billing infra exists yet; this needs a product decision before it's designed, not an engineering default.


## Release

- [ ] **Launch on the Play Store.** the usual store-listing work: screenshots, privacy policy URL, data safety questionnaire, content rating, and a closed testing track before production. Also needs a real release signing config — `release.yml`'s `flutter build apk --release` artifact is still built with the debug signing config (`mobile/android/app/build.gradle`'s `release` block points at `signingConfigs.getByName("debug")`).

