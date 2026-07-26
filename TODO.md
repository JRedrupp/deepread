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
- [ ] User-settable feed names. Feeds currently show their raw URL as the display name (`feed.title ?? feed.url` in `FeedListScreen`, and `feeds.title` is never actually populated server-side) — let the user rename a feed to something readable.
- [ ] Delete/unsubscribe a feed. There's currently no way to remove a feed once added — needs a delete on `user_feed_subscriptions` (and probably a local cleanup of downloaded articles for that feed too).
- [ ] Delete an Article on local device. (need to then make sure it doesn't get re downloaded
- [ ] Combined "all articles" view across every subscribed feed, so the user doesn't have to open each feed individually to see what's new.
- [ ] "Last synced" timestamp shown in the UI (e.g. next to the sync button in `FeedListScreen`) — currently sync happens with no visible indication of when it last ran or succeeded.
- [ ] Settings page — a home for sign-out (currently just an app bar icon), last-synced info, and future preferences (theme, retention, etc.) rather than piling everything into the feed list app bar.
- [ ] Link to the app's GitHub repo somewhere in the app (e.g. settings page once it exists).
- [ ] Audio Reader - can we make use of iOS and Android native TTS
- [ ] Link to the original article's live URL from the reader screen, so the user can open it in a real browser when online (useful when the offline render is imperfect, e.g. the Readability edge cases noted in TECH_DEBT.md).

## Bugs

- [ ] **Renderer fails on pages with a strict script-src CSP (e.g. GitHub repo pages, Discourse forums).** `_render_with_playwright` (`backend/deepread_worker/renderer.py:125`) injects Readability via `page.add_script_tag(content=_READABILITY_JS)`, which adds an inline `<script>`. Sites whose CSP `script-src` doesn't allow `'unsafe-inline'` block it, so `add_script_tag` raises and the article fails to render. Seen on `https://github.com/mulfyx/w4me-station` (`script-src github.githubassets.com`) and `https://discuss.grapheneos.org/d/40700-...` (Discourse's hashed/allowlisted `script-src`). Needs a CSP-safe injection method, e.g. `page.add_init_script` before navigation, or evaluating Readability via `page.evaluate` with the script content passed as a function argument instead of an injected `<script>` tag.

## Storage & scaling

- [ ] Automated retention policy (auto-expire read articles, or cap articles per feed) — MVP keeps everything until manually deleted
- [ ] Per-user rate limiting/quotas on feed adds — MVP has no cost-abuse protection beyond basic sanity limits
- [ ] Admin/observability view for failed renders & dead-lettered articles
- [ ] Split poller/renderer into separate services with a real queue (Redis) once usage justifies it — MVP uses a single worker process with `articles.status` as an implicit queue

## Business

- [ ] **Monetization/billing model — explicitly undecided.** No billing infra exists yet; this needs a product decision before it's designed, not an engineering default.


## Release

- [ ] **Launch on the Play Store.** the usual store-listing work: screenshots, privacy policy URL, data safety questionnaire, content rating, and a closed testing track before production.
