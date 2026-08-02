# forceFullFetch retry-signal fix — design

## Problem

`SyncService.syncNow` (`mobile/lib/features/sync/sync_service.dart`) needs to force an
unwatermarked (`forceFullFetch: true`) fetch whenever a feed subscription might have an
already-rendered back catalog this device hasn't pulled yet — `articles`/`feeds` are a *shared*
rendering cache, so a feed's articles can have been rendered long before this user (or device)
subscribed to it, and a plain `.gt('rendered_at', since)` pass would permanently skip anything
rendered before the current watermark.

There are two ways a subscription can need this:

1. **This device subscribes**, via `FeedRepository.subscribe`. That method writes the local
   `LocalFeeds` row itself, synchronously, before the next sync pass ever runs — so by the time
   `SyncService` gets a chance to compare local vs. remote feed rows, the feed is already "known."
   This path already has a fix: `subscribe` calls `markPendingFullFetch`, which sets a persisted
   `SyncState.needsFullFetch` flag that `syncNow` reads and only clears after a full fetch
   *succeeds* — a failed pass leaves it set, so it's retried.
2. **Another device subscribes**, and this device first learns about it from the
   `user_feed_subscriptions` pull inside `SyncService._syncFeeds`. This path has no durable flag —
   `_syncFeeds` derives `hasNewSubscription` fresh every call, by comparing the pulled feed ids
   against `LocalFeeds` rows already present locally. But `_syncFeeds` also upserts the local feed
   row **in the same loop iteration**, before `syncArticles` ever runs. So the signal is consumed
   and destroyed in one pass: if the forced `syncArticles` call then fails (any single article's
   download/unzip error is enough — see the per-article failure isolation this file already has),
   the next `syncNow` call sees the feed already present in `LocalFeeds`, computes
   `hasNewSubscription = false`, and — since `needsFullFetch` was never set for this path — sends a
   normal watermarked fetch. Everything in that feed's back catalog older than the current
   watermark is now permanently invisible. This is TODO.md's third MVP item, narrowed: path 1 above
   was fixed separately (see `needsFullFetch`'s own history); this is the surviving gap.

This is silent, permanent data loss for the affected feed's pre-watermark articles — not a
transient failure that self-heals on retry, since nothing about the next pass differs from a
successful one.

## Goal

Give path 2 the same durability path 1 already has: one persisted `needsFullFetch` flag, set
before the local feed row becomes "known" and cleared only once a forced fetch has actually
succeeded — so `syncNow` never needs a fresh-every-call `hasNewSubscription` comparison at all.

Out of scope:
- Retroactively rescuing feeds already stranded under the current (pre-fix) code — this only
  prevents new occurrences going forward. A one-off is a straightforward follow-up
  (`UPDATE sync_state SET needs_full_fetch = true` on affected devices, or simpler, uninstall/data
  clear) but isn't part of this change.
- `syncNow`/`_syncFeeds` remain untestable directly (both touch the static `AppSupabase.client`) —
  same pre-existing limitation the pagination fix's design doc notes for this file. The fix is
  structured so the new logic lives in a plain, DB-only, directly-testable function instead.

## Design

### One signal, set at the point of detection

Fold `_syncFeeds`'s `hasNewSubscription` comparison into the same `markPendingFullFetch` signal
`FeedRepository.subscribe` already uses, instead of running two parallel mechanisms that `syncNow`
then ORs together. Extract the per-feed-row decision into a new top-level function,
`syncFeedRows(AppDatabase db, List<Map<String, dynamic>> feeds)`, mirroring this file's existing
pattern of keeping decision logic in a plain, unit-testable function separate from the I/O that
drives it (`decideArticleSyncAction` is the precedent):

```dart
Future<void> syncFeedRows(AppDatabase db, List<Map<String, dynamic>> feeds) async {
  final existingIds = (await db.select(db.localFeeds).get()).map((f) => f.id).toSet();

  for (final feed in feeds) {
    final feedId = feed['id'] as String;
    if (!existingIds.contains(feedId)) await markPendingFullFetch(db);
    await db.into(db.localFeeds).insertOnConflictUpdate(
          LocalFeedsCompanion.insert(
            id: feedId,
            url: feed['url'] as String,
            title: Value(feed['title'] as String?),
          ),
        );
  }
}
```

`_syncFeeds` shrinks to fetching the remote rows and delegating:

```dart
Future<void> _syncFeeds(String userId) async {
  final rows = await AppSupabase.client
      .from('user_feed_subscriptions')
      .select('feeds(id, url, title)')
      .eq('user_id', userId);
  final feeds = (rows as List).map((row) => row['feeds'] as Map<String, dynamic>).toList();
  await syncFeedRows(db, feeds);
}
```

`_syncFeeds` no longer returns anything — its `bool` return existed only to carry
`hasNewSubscription` back to `syncNow`, which no longer needs it. `syncNow` simplifies to reading
the one durable flag:

```dart
Future<void> syncNow() async {
  final userId = AppSupabase.client.auth.currentUser?.id;
  if (userId == null) return;

  await _syncFeeds(userId);
  final pendingFullFetch = await hasPendingFullFetch(db);
  await syncArticles(forceFullFetch: pendingFullFetch);

  if (pendingFullFetch) await clearPendingFullFetch(db);
}
```

**Ordering is the crux of the fix, twice over:**

- Inside `syncFeedRows`, `markPendingFullFetch` must run *before* the `insertOnConflictUpdate` for
  a feed not yet in `existingIds`. If the local row were written first and the process died before
  the flag write, the feed would look "already known" on the next call with no flag ever set —
  recreating exactly the bug this change fixes.
- The same reordering applies to `FeedRepository.subscribe` (`mobile/lib/data/remote/feed_repository.dart`),
  which currently writes its local `LocalFeeds` row *before* calling `markPendingFullFetch`. Same
  failure shape, same fix: swap the two calls so the flag is set first. This is a two-line change,
  not a new mechanism — `markPendingFullFetch` is already imported and used there.

### What `syncNow` no longer needs

The `hasNewSubscription || pendingFullFetch` OR in the current code, and the comment explaining why
both signals exist, both go away — there's one signal now, always durable, regardless of which of
the two call sites set it.

### Non-goals / accepted risk

- **Extra network cost, not correctness risk.** Both paths already re-examine already-synced
  articles on a forced full fetch cheaply via `ArticleSyncAction.skip` — unchanged by this design.
- **`FeedRepository.subscribe`'s remaining non-atomicity** (the remote subscription insert and the
  local writes are still separate steps, each individually retriable) is pre-existing and untouched
  — only the *order* of the two local writes changes.

### Testing (`mobile/test/sync_service_test.dart`)

`syncFeedRows` is DB-only (no `AppSupabase` calls), so it's directly testable the same way
`decideArticleSyncAction` and `hasPendingFullFetch`/`markPendingFullFetch` already are:

- A feed id not present in `LocalFeeds` gets inserted *and* marks `needsFullFetch`.
- A feed id already present in `LocalFeeds` gets its row upserted (e.g. a title change) *without*
  re-marking `needsFullFetch`.

Plus one regression test composing `syncFeedRows` and `SyncService.syncArticles` the way `syncNow`
does internally (`syncNow` itself stays untested directly, consistent with the rest of this file),
reproducing the exact bug this change fixes across two simulated passes:

1. Pass 1: `syncFeedRows` sees a feed not yet local (sets the flag) against a pre-existing
   watermark from other feeds' prior syncs. A forced `syncArticles` call then fails on one article.
2. Pass 2: `syncFeedRows` is called again with the same feed — now present locally from pass 1's
   upsert, so a fresh "is this new" comparison would say no. Assert the flag, read fresh, is still
   `true`, and that a `syncArticles(forceFullFetch: true)` call requests `since: null` rather than
   the pre-existing watermark.

Run against the current (pre-fix) code with only `_syncFeeds`'s comparison and no persisted flag
for this path, step 2 would compute `forceFullFetch: false` and request the stale watermark instead
— this test fails on that code and passes once `syncFeedRows` is wired in.
