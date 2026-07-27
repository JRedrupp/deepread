# TODO

## MVP — remaining (not yet built, not deferred)

Auth screens, the sync service, and add-feed wiring are now built and working end-to-end. What's left from the original MVP scope:

- [ ] **iOS background fetch config.** `BackgroundSync.register()` (`mobile/lib/features/sync/background_sync.dart`) calls `Workmanager().registerPeriodicTask`, but iOS also needs a `BGTaskSchedulerPermittedIdentifiers` entry in `Info.plist` (and corresponding native setup) that hasn't been added — registration is wrapped in try/catch so this fails soft rather than crashing the app, but background sync silently won't run on iOS until this is done.
- [ ] **Prompt the user to exempt DeepRead from OEM battery restrictions.** Confirmed on a Samsung device (One UI, Android 16) that `BackgroundSync`'s periodic WorkManager task can sit enqueued indefinitely (`run_attempt_count=0` in WorkManager's own `workdb`) because the OS applies a manufacturer-specific network block (`REASON_OEM_DENY` in `dumpsys jobscheduler`'s `ConnectivityController`) independent of Doze, App Standby, Data Saver, and Battery Saver — none of which the app can detect or work around in code. This isn't in Samsung's "Sleeping apps" list either, just the default "Optimised" per-app battery mode. The app should detect this isn't set (or just always show a one-time prompt/banner) and guide the user to set Battery mode to "Unrestricted" for DeepRead (`Settings > Apps > DeepRead > Battery`), otherwise background sync silently never runs on affected devices.
- [ ] **Sync doesn't paginate a single fetch, and an oversized first sync now permanently truncates.** `SyncService.syncArticles` added a `rendered_at` watermark so steady-state passes only fetch newly-ready/re-rendered rows, but a single pass is still one uncapped query — no `.limit()`/pagination. Previously a PostgREST-row-cap-truncated fetch was self-healing (the old code had no watermark, so it just refetched everything, including the truncated remainder, on the next pass); now the watermark advances to the max `rendered_at` seen in that page, so a truncated page **permanently** strands whatever didn't fit. Needs `.order('rendered_at').limit(N)` paging with the watermark only advancing once a full pass is confirmed complete (e.g. don't advance it at all if the page came back at the cap).
- [ ] **Sync doesn't isolate per-article failures.** `SyncService._downloadAndStore` has no try/catch around individual articles — one bad zip download aborts the rest of that sync pass. The backend renderer already isolates per-article failures; the client sync loop should too.

Everything below this section is genuinely deferred/out-of-scope for the MVP, not missing MVP work.

## Features

- [ ] Feed auto-discovery + OPML import (MVP is paste-URL only)
- [ ] Push notifications (FCM/APNs) to trigger faster sync (MVP polls on open + background fetch only)
- [ ] Starring/favoriting articles
- [ ] Folders/tags for feeds
- [ ] Full-text search across downloaded articles (SQLite FTS5)
- [ ] Desktop platform support (Linux/macOS/Windows) — MVP is Android + iOS only
- [ ] Cross-device sync of read/starred state — currently local-only per device
- [ ] User-settable feed names. Feeds currently show their raw URL as the display name (`feed.title ?? feed.url` in `FeedListScreen`, and `feeds.title` is never actually populated server-side) — let the user rename a feed to something readable.
- [ ] Delete/unsubscribe a feed. There's currently no way to remove a feed once added — needs a delete on `user_feed_subscriptions` (and probably a local cleanup of downloaded articles for that feed too).
- [ ] Delete an Article on local device. (need to then make sure it doesn't get re downloaded
- [ ] Combined "all articles" view across every subscribed feed, so the user doesn't have to open each feed individually to see what's new.
- [ ] "Last synced" timestamp shown in the UI (e.g. next to the sync button in `FeedListScreen`) — currently sync happens with no visible indication of when it last ran or succeeded.
- [ ] Settings page — a home for sign-out (currently just an app bar icon), last-synced info, and future preferences (theme, retention, etc.) rather than piling everything into the feed list app bar.
- [ ] Link to the app's GitHub repo somewhere in the app (e.g. settings page once it exists).
- [ ] Audio Reader - can we make use of iOS and Android native TTS
- [ ] Link to the original article's live URL from the reader screen, so the user can open it in a real browser when online (useful when the offline render is imperfect, e.g. the Readability edge cases noted in TECH_DEBT.md).

## Storage & scaling

- [ ] Automated retention policy (auto-expire read articles, or cap articles per feed) — MVP keeps everything until manually deleted
- [ ] Per-user rate limiting/quotas on feed adds — MVP has no cost-abuse protection beyond basic sanity limits
- [ ] Admin/observability view for failed renders & dead-lettered articles
- [ ] Split poller/renderer into separate services with a real queue (Redis) once usage justifies it — MVP uses a single worker process with `articles.status` as an implicit queue

## Tooling

- [ ] Auto-apply Supabase migrations on release — `supabase/migrations/` is still pasted into the SQL Editor by hand per `supabase/README.md`. Would hook into `.github/workflows/release.yml` alongside the backend deploy step, but needs the Supabase CLI project link set up first (not present in this repo yet).

## Business

- [ ] **Monetization/billing model — explicitly undecided.** No billing infra exists yet; this needs a product decision before it's designed, not an engineering default.


## Release

- [ ] **Launch on the Play Store.** the usual store-listing work: screenshots, privacy policy URL, data safety questionnaire, content rating, and a closed testing track before production.

