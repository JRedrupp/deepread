# Combined "all articles" view — design

## Problem

Today `FeedListScreen` is the app's home screen with no bottom navigation. Reading anything
requires opening a feed first, then its `ArticleListScreen` (filtered to `LocalArticles.feedId ==
that feed`). With more than a couple of subscriptions this means checking each feed individually to
find what's new — there's no single place to see everything downloaded across every subscription.
This is a tracked TODO.md item ("Combined 'all articles' view across every subscribed feed").

## Design

### 1. Navigation architecture

A new `HomeShell` widget (`mobile/lib/features/home/home_shell.dart`) becomes the app's home,
replacing the current direct `AuthGate → FeedListScreen` wiring. It owns:

- One shared `Scaffold` with a single `AppBar` (sync button + settings icon — same behavior as
  today) and a bottom `NavigationBar` with two destinations: **Feeds** and **All Articles**.
- State that is really app-global, moved up from `FeedListScreen`: `_syncing`, `_syncFuture`,
  `_syncNow()`, `_signOut()`.
- An `IndexedStack` body so switching tabs preserves each tab's scroll position and drift stream
  subscription instead of tearing it down.
- The "add feed" FAB is tab-scoped — only shown while the Feeds tab is selected.
- Sort/filter state for the All Articles tab (`_unreadOnly`, `_sortOrder`) is lifted to
  `HomeShell` too, since the icons that control them live in the shared AppBar's `actions` and
  must only appear while that tab is active.

`FeedListScreen` becomes a body-only widget: no more own `AppBar`/`Scaffold`, just the feed
`ListView` + tap-to-open-`ArticleListScreen` + unsubscribe menu. It receives `onSyncNow`/`onAddFeed`
callbacks from `HomeShell` instead of owning that logic itself. Tapping a specific feed still
pushes the existing `ArticleListScreen` unchanged, with its own AppBar and feed-scoped query.

### 2. New "All Articles" screen

`mobile/lib/features/articles/all_articles_screen.dart` — body-only, lives inside `HomeShell`'s
`IndexedStack`. Same two controls as `ArticleListScreen` today: unread-only filter and
newest/oldest sort, both driven by state now living in `HomeShell` and passed down.

List ordering: flat, chronological across every feed (same `publishedAt ?? downloadedAt` sort
`ArticleListScreen` already uses) — not grouped/sectioned by feed. Each row gets a feed-name badge
so the source is still visible in a flat list.

To avoid duplicating the per-article card body (title, `[NEW]`/`[SUMMARY ONLY]`/`[REMOVED]` tags,
date), extract the existing `ListTile` content out of `ArticleListScreen` into a shared private
widget parameterized with an optional `feedLabel: String?`. `ArticleListScreen` passes nothing (the
feed is already implied by its own AppBar title); `AllArticlesScreen` passes the joined feed name.

### 3. Data layer

`LocalArticles` only stores `feedId` — no denormalized feed title — so the combined view needs a
join. Three options considered:

- **Chosen: a drift join query.** One query joining `LocalArticles` ⋈ `LocalFeeds` on `feedId`,
  watched as a single `Stream<List<ArticleWithFeed>>`, where `ArticleWithFeed` is a small
  `({LocalArticle article, String feedDisplayName})` record. `feedDisplayName` is computed as
  `feed.title ?? feed.url`, the same fallback `FeedListScreen` already uses. Single source of
  truth, no staleness risk, minimal new code.
- **Rejected: combine two separate streams client-side** (watch articles and feeds independently,
  merge via a `feedId → title` map rebuilt on every emission). More moving parts for no benefit at
  this scale.
- **Rejected: denormalize `feedTitle` onto `LocalArticles`.** Avoids the join, but duplicates data
  that can drift out of sync (feed renaming is an open TODO item) and needs a backfill migration
  for existing rows — worse trade-off than a plain join for a local, small-scale cache.

The join lives as a method on `AppDatabase` (or a thin query class alongside `database.dart`).

`AllArticlesScreen` takes an injectable `Stream<List<ArticleWithFeed>>? articlesStream` parameter
defaulting to the live joined query — the same pattern `ArticleListScreen.articlesStream` and
`FeedListScreen.feedsStream` already use, required by the drift-in-`testWidgets`-fake-async
limitation documented in TECH_DEBT.md.

No pagination: this mirrors `ArticleListScreen`'s current unpaginated `ListView`. Article counts
here are bounded by the same on-device `RetentionService` settings as the per-feed view, just
unioned across feeds instead of scoped to one.

### 4. Error handling

No new error handling needed. Sync failures already surface via the snackbar in
`HomeShell._syncNow` (moved from `FeedListScreen`, unchanged behavior). An empty combined list
shows the same "No articles downloaded yet." / "No unread articles." messaging `ArticleListScreen`
already shows for an empty/filtered result.

### 5. Visual styling

Kept consistent with the existing dev-tool-inspired theme (`mobile/lib/theme/app_theme.dart`:
dark-by-default, JetBrains Mono metadata, flat 1px-bordered cards, bracket-style `StatusTag`s)
rather than reaching for stock Material 3 defaults:

- **Bottom nav bar**: not the Material 3 pill-indicator `NavigationBar` default. Background matches
  `AppTheme.background`/`surface`, a 1px top hairline in the existing `border` color (matching the
  card border language already used elsewhere), active tab indicated by accent-teal (`AppTheme.
  accent`) icon+label color rather than a filled indicator pill.
- **Feed-name badge**: not a Material `Chip` (filled pill, elevation). A plain bracketed monospace
  tag in the same family as `StatusTag`, e.g. `[The Verge]`, reusing `AppTheme.metadataStyle`. Sits
  first in the metadata row, ahead of `[NEW]`/date, since it's the new grouping identifier this
  view adds that the per-feed view doesn't need.

### 6. Testing

- Unit-test the joined query against a real in-memory drift DB (`AppDatabase.forTesting`): insert a
  couple of `LocalFeeds`/`LocalArticles` rows, assert the stream emits the right `feedDisplayName`
  per article, including the `title ?? url` fallback.
- Widget tests for `AllArticlesScreen` pass `Stream.value([...])` via the injectable param, same as
  the existing `ArticleListScreen` tests — covers sort toggle, unread filter, and feed-badge
  rendering.
- `HomeShell` widget tests: inject fake streams/callbacks for both tabs' content, assert
  tab-switching swaps the body and the AppBar's conditional actions (filter/sort icons only visible
  on the All Articles tab) without losing either tab's state.
- Existing `FeedListScreenTest` needs updating for the narrowed widget (no more own AppBar/sync
  button — those assertions move to a new `HomeShellTest`).

### 7. Housekeeping

- `TODO.md`: remove the "Combined 'all articles' view across every subscribed feed" line once
  this ships — it's the item this design implements.

## Non-goals / accepted scope

- **No filter-by-specific-feed within the combined view.** The Feeds tab already covers "articles
  from one feed"; adding a feed-filter chip row to All Articles would duplicate that.
- **No grouping/sectioning by feed.** Explicitly decided against — flat chronological order with a
  per-row feed badge, matching the existing per-feed screen's mental model rather than introducing
  a new list structure.
- **Feed badge is not tappable.** No navigation-to-that-feed affordance from the badge; out of
  scope for this feature.
- **No pagination/lazy-loading.** Same accepted scale assumption `ArticleListScreen` already makes.
