# TODO

## MVP — remaining (not yet built, not deferred)

Auth screens, the sync service, and add-feed wiring are now built and working end-to-end. What's left from the original MVP scope:

- [ ] **iOS background fetch config.** `BackgroundSync.register()` (`mobile/lib/features/sync/background_sync.dart`) calls `Workmanager().registerPeriodicTask`, but iOS also needs a `BGTaskSchedulerPermittedIdentifiers` entry in `Info.plist` (and corresponding native setup) that hasn't been added — registration is wrapped in try/catch so this fails soft rather than crashing the app, but background sync silently won't run on iOS until this is done.
- [ ] **Sync doesn't paginate a single fetch, and an oversized first sync now permanently truncates.** `SyncService.syncArticles` added a `rendered_at` watermark so steady-state passes only fetch newly-ready/re-rendered rows, but a single pass is still one uncapped query — no `.limit()`/pagination. Previously a PostgREST-row-cap-truncated fetch was self-healing (the old code had no watermark, so it just refetched everything, including the truncated remainder, on the next pass); now the watermark advances to the max `rendered_at` seen in that page, so a truncated page **permanently** strands whatever didn't fit. Needs `.order('rendered_at').limit(N)` paging with the watermark only advancing once a full pass is confirmed complete (e.g. don't advance it at all if the page came back at the cap).
- [ ] **A failure during a `forceFullFetch` pass can permanently strand a newly-subscribed feed's back catalog.** `syncNow` (`sync_service.dart`) passes `forceFullFetch: true` exactly once, on the pass a new subscription is detected, to bypass the watermark and pick up that feed's already-rendered older articles. If any row in that one-shot full fetch fails, `syncArticles` withholds the watermark write (correct — see the per-article-failure-isolation comment above it), but on the *next* pass `_syncFeeds` no longer reports the subscription as new (it's already in `localFeeds`), so `syncNow` won't pass `forceFullFetch` again — the failed back-catalog row is never retried. Pre-existing behavior (the old code had the same all-or-nothing outcome via an uncaught exception aborting the pass before the watermark write), not introduced by the per-article isolation work. Needs `forceFullFetch` to be re-derived from "is there a locally-subscribed feed with no synced articles yet" rather than a one-shot flag, or some other durable signal that survives past the single pass.

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

## Business

- [ ] **Monetization/billing model — explicitly undecided.** No billing infra exists yet; this needs a product decision before it's designed, not an engineering default.


## Release

- [ ] **Launch on the Play Store.** the usual store-listing work: screenshots, privacy policy URL, data safety questionnaire, content rating, and a closed testing track before production.

