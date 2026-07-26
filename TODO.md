# TODO

## MVP — remaining (not yet built, not deferred)

Auth screens, the sync service, and add-feed wiring are now built and working end-to-end. What's left from the original MVP scope:

- [ ] **Paywalled-article representation on the client.** The backend already stores an RSS `summary` and leaves `storage_path` null for paywalled articles, but `LocalArticles.localPath` (`mobile/lib/data/local/database.dart`) is non-nullable and there's no local `summary` column, so the sync service currently just skips these rows (`SyncService._syncArticles`) instead of showing anything. Needs: nullable `localPath` + a `summary` column locally, and a summary-only display path in `ArticleReaderScreen` instead of a blank WebView.
- [ ] **iOS background fetch config.** `BackgroundSync.register()` (`mobile/lib/features/sync/background_sync.dart`) calls `Workmanager().registerPeriodicTask`, but iOS also needs a `BGTaskSchedulerPermittedIdentifiers` entry in `Info.plist` (and corresponding native setup) that hasn't been added — registration is wrapped in try/catch so this fails soft rather than crashing the app, but background sync silently won't run on iOS until this is done.
- [ ] **Sign-out doesn't clear local data.** `AuthGate` swaps to the login screen, but the local `drift` DB (`LocalFeeds`/`LocalArticles`) and unzipped article files on disk aren't cleared. Signing in as a different user on the same device currently shows the previous user's feeds — a real problem for a public multi-user app, not just a cosmetic one.
- [ ] **Sync doesn't paginate or scope by time.** `SyncService._syncArticles` fetches *every* `status='ready'` article for the user's subscriptions on every sync pass, with no limit/watermark — this will eventually hit PostgREST's default row cap and is wasteful background-fetch work under iOS's tight time budget. Needs a `rendered_at` watermark (only fetch articles rendered since the last successful sync) or pagination.
- [ ] **Sync doesn't isolate per-article failures.** `SyncService._downloadAndStore` has no try/catch around individual articles — one bad zip download aborts the rest of that sync pass. The backend renderer already isolates per-article failures; the client sync loop should too.
- [ ] **No re-download path when a server-side article is re-rendered.** `SyncService._syncArticles` skips any article ID already present locally (`if (alreadyDownloaded != null) continue`), so if the backend re-renders an article (bug fix, template change, retry after a failure) the client never picks up the new version — discovered when a packaging template fix required manually clearing app data to see it reflected. Pairs naturally with the watermark item above: compare remote `rendered_at` against the locally stored download, not just presence/absence of the row.

Everything below this section is genuinely deferred/out-of-scope for the MVP, not missing MVP work.

## Features

- [ ] Feed auto-discovery + OPML import (MVP is paste-URL only)
- [ ] Push notifications (FCM/APNs) to trigger faster sync (MVP polls on open + background fetch only)
- [ ] Starring/favoriting articles
- [ ] Folders/tags for feeds
- [ ] Full-text search across downloaded articles (SQLite FTS5)
- [ ] Desktop platform support (Linux/macOS/Windows) — MVP is Android + iOS only
- [ ] Cross-device sync of read/starred state — currently local-only per device

## Storage & scaling

- [ ] Automated retention policy (auto-expire read articles, or cap articles per feed) — MVP keeps everything until manually deleted
- [ ] Per-user rate limiting/quotas on feed adds — MVP has no cost-abuse protection beyond basic sanity limits
- [ ] Admin/observability view for failed renders & dead-lettered articles
- [ ] Split poller/renderer into separate services with a real queue (Redis) once usage justifies it — MVP uses a single worker process with `articles.status` as an implicit queue

## Business

- [ ] **Monetization/billing model — explicitly undecided.** No billing infra exists yet; this needs a product decision before it's designed, not an engineering default.

## Legal (blocking gates before public launch)

- [ ] **Legal review of the shared-caching model before any real public launch.** The MVP includes paywall-avoidance, robots.txt respect, and a takedown-request flow as mitigations, but these reduce risk — they don't substitute for actual legal review once this has real users.
- [ ] Register a DMCA agent (US Copyright Office, ~$6 one-time) before public launch, to become eligible for safe-harbor protection.
