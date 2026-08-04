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
- [ ] User-settable feed names. Feeds currently show their raw URL as the display name (`feed.title ?? feed.url` in `FeedListScreen`, and `feeds.title` is never actually populated server-side) — let the user rename a feed to something readable. The combined all-articles view's per-article feed badge (`ArticleListTile`) now makes this gap more visible too, since it falls back to the raw feed URL there as well — worth fixing together.
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
- [ ] **Revisit the `workmanager` pin + `dependency_overrides` in `mobile/pubspec.yaml` once Flutter 3.47 is stable.** Pinned because `workmanager_android` needs AGP 9's built-in Kotlin, but this project's `android/gradle.properties` sets `android.builtInKotlin=false` (Flutter's own template default). Flipping that flag to `true` doesn't work yet either — Flutter's plugin loader force-applies the legacy `kotlin-android` plugin to any subproject that doesn't self-declare KGP (e.g. `app_links`, pulled in via `supabase_flutter`), which collides with AGP 9's built-in compiler. That's a known Flutter bug ([flutter/flutter#189133](https://github.com/flutter/flutter/issues/189133), fixed by #188543) that only ships starting Flutter 3.47 — beta only as of writing, not yet in stable. Once on 3.47+, try flipping `android.builtInKotlin=true` (and dropping `android.newDsl=false`) and unpinning `workmanager`/removing the three `workmanager_*` overrides in one go.

## Business

- [ ] **Monetization/billing model — explicitly undecided.** No billing infra exists yet; this needs a product decision before it's designed, not an engineering default.


## Release

- [ ] **Launch on the Play Store.** the usual store-listing work: screenshots, privacy policy URL, data safety questionnaire, content rating, and a closed testing track before production. Also needs a real release signing config — `release.yml`'s `flutter build apk --release` artifact is still built with the debug signing config (`mobile/android/app/build.gradle`'s `release` block points at `signingConfigs.getByName("debug")`).

