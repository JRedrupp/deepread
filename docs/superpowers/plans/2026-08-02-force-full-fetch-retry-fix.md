# forceFullFetch Retry-Signal Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the surviving half of TODO.md's "forceFullFetch strand" bug: a feed subscription
first detected via `SyncService._syncFeeds` (i.e. subscribed on a *different* device) has no
durable retry signal, so if the forced back-catalog fetch it triggers fails partway, the next
sync pass silently reverts to a normal watermarked fetch and permanently strands whatever in that
feed's back catalog predates the current watermark.

**Architecture:** Extract `_syncFeeds`'s per-feed local-row logic into a new top-level, DB-only
function `syncFeedRows`, which marks the same persisted `SyncState.needsFullFetch` flag
`FeedRepository.subscribe` already uses (via `markPendingFullFetch`) for any feed not yet known
locally — set *before* the local row write, not after, so a crash between the two can't destroy
the signal. `syncNow` then reads one durable flag instead of ORing it with a fresh-every-call
comparison. `FeedRepository.subscribe`'s existing two calls get reordered the same way, closing the
identical gap on that path.

**Tech Stack:** Flutter/Dart, `drift` (SQLite), `supabase_flutter` (PostgREST query builder),
`flutter_test`.

## Global Constraints

- No changes to `SyncService.syncArticles`'s pagination logic (already fixed separately — see
  `docs/superpowers/specs/2026-08-02-sync-pagination-fix-design.md`).
- `syncNow` and `_syncFeeds` stay untested directly (both touch the static `AppSupabase.client`,
  same pre-existing limitation as the rest of this file) — the new logic must live in a function
  that doesn't, so it's directly testable.
- Design reference: `docs/superpowers/specs/2026-08-02-force-full-fetch-retry-fix-design.md`.

---

### Task 1: Extract `syncFeedRows` and give it the durable full-fetch signal

**Files:**
- Modify: `mobile/lib/features/sync/sync_service.dart`
- Modify: `mobile/test/sync_service_test.dart`

**Interfaces:**
- Consumes: `markPendingFullFetch(AppDatabase db)`, `hasPendingFullFetch(AppDatabase db)` (both
  already exist in this file, unchanged).
- Produces:
  - `Future<void> syncFeedRows(AppDatabase db, List<Map<String, dynamic>> feeds)` — new top-level
    function. `feeds` is a list of `{'id': String, 'url': String, 'title': String?}` maps (the
    shape already produced by `_syncFeeds`'s Supabase query). Upserts each into `LocalFeeds`;
    marks `needsFullFetch` first for any feed id not already present locally.
  - `SyncService._syncFeeds(String userId)` return type changes from `Future<bool>` to
    `Future<void>` — its caller (`syncNow`) no longer needs a return value.

- [ ] **Step 1: Add the two `syncFeedRows` unit tests (RED)**

Insert a new test group immediately after the existing `pending full fetch signal` group's closing
`});` (currently `mobile/test/sync_service_test.dart:193`) and before `group('SyncService.syncArticles'`
(currently line 195):

```dart
  group('syncFeedRows', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('inserts the local row and marks pendingFullFetch for a feed not seen before', () async {
      await syncFeedRows(db, [
        {'id': 'feed-1', 'url': 'https://example.com/feed', 'title': 'Example'},
      ]);

      expect(await hasPendingFullFetch(db), isTrue);
      final stored = await (db.select(db.localFeeds)..where((f) => f.id.equals('feed-1'))).getSingle();
      expect(stored.url, 'https://example.com/feed');
      expect(stored.title, 'Example');
    });

    test('updates an already-known feed row without marking pendingFullFetch', () async {
      await db.into(db.localFeeds).insert(
            LocalFeedsCompanion.insert(id: 'feed-1', url: 'https://example.com/feed'),
          );

      await syncFeedRows(db, [
        {'id': 'feed-1', 'url': 'https://example.com/feed', 'title': 'New Title'},
      ]);

      expect(await hasPendingFullFetch(db), isFalse);
      final stored = await (db.select(db.localFeeds)..where((f) => f.id.equals('feed-1'))).getSingle();
      expect(stored.title, 'New Title');
    });
  });

```

This won't compile yet — `syncFeedRows` doesn't exist. That's the RED state for this step.

- [ ] **Step 2: Run the test file and confirm it fails to compile**

Run: `cd mobile && flutter test test/sync_service_test.dart`
Expected: compile error — `The function 'syncFeedRows' isn't defined`.

- [ ] **Step 3: Add `syncFeedRows` and rewire `_syncFeeds`/`syncNow` (GREEN)**

In `mobile/lib/features/sync/sync_service.dart`, insert this new function directly after
`clearPendingFullFetch` (currently ending at line 133) and before `_defaultRecordLastSynced`:

```dart

/// Upserts each remote feed row into [LocalFeeds], marking the durable
/// [markPendingFullFetch] signal first for any feed not already known on
/// this device. This is the counterpart to [FeedRepository.subscribe]'s own
/// call to [markPendingFullFetch]: that path covers this device doing the
/// subscribing, this one covers a subscription made on a *different*
/// device that first shows up here via the `user_feed_subscriptions` pull.
/// Marking before the local row is written (not after) matters: once the
/// row exists, there is no other signal that this feed's back catalog was
/// ever pending — see the design doc referenced in
/// `docs/superpowers/specs/2026-08-02-force-full-fetch-retry-fix-design.md`.
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

Then replace `syncNow` and `_syncFeeds` (currently lines 195–246) with:

```dart
  Future<void> syncNow() async {
    final userId = AppSupabase.client.auth.currentUser?.id;
    if (userId == null) return;

    await _syncFeeds(userId);
    final pendingFullFetch = await hasPendingFullFetch(db);
    // A newly-subscribed feed's already-rendered back catalog predates the
    // current watermark (this is a *shared* rendering cache — a feed's
    // articles can have been rendered long before this user subscribed),
    // so a plain `.gt('rendered_at', since)` pass would permanently skip
    // them. needsFullFetch is the single durable signal for this: set by
    // syncFeedRows (above, via _syncFeeds) when a subscription made on
    // another device first shows up here, or by FeedRepository.subscribe
    // when this device does the subscribing. "Durable" is the whole point
    // — it survives a failed pass (this line is skipped entirely if
    // syncArticles below throws) rather than being derived fresh each pass
    // from "is the feed row already in LocalFeeds", which stops working
    // the moment that row gets written.
    await syncArticles(forceFullFetch: pendingFullFetch);

    // Only clear once the full fetch above has actually completed — if it
    // threw, this line is never reached, so the signal survives for the
    // next pass to retry rather than being silently lost.
    if (pendingFullFetch) await clearPendingFullFetch(db);
  }

  /// Pulls the current subscription list and syncs local feed rows —
  /// delegates the actual decision/write logic to [syncFeedRows] so that
  /// logic can be unit-tested without touching [AppSupabase.client].
  Future<void> _syncFeeds(String userId) async {
    final rows = await AppSupabase.client
        .from('user_feed_subscriptions')
        .select('feeds(id, url, title)')
        .eq('user_id', userId);

    final feeds = (rows as List).map((row) => row['feeds'] as Map<String, dynamic>).toList();
    await syncFeedRows(db, feeds);
  }
```

- [ ] **Step 4: Run the sync test file and confirm the new tests pass**

Run: `cd mobile && flutter test test/sync_service_test.dart`
Expected: PASS — the two new `syncFeedRows` tests, plus every pre-existing test in this file
(`decideArticleSyncAction`, `pending full fetch signal`, `SyncService.syncArticles`) unaffected,
since none of them call `_syncFeeds`/`syncNow` directly.

- [ ] **Step 5: Add the two-pass regression test (RED — reproduces the original bug)**

Insert this test at the end of the `SyncService.syncArticles` group, immediately before that
group's closing `});` (currently `mobile/test/sync_service_test.dart:740`, right after the
`legacy backfill path...` test ends at line 739):

```dart

    test('a feed first detected via syncFeedRows survives a failed forced pass and still '
        'forces a full fetch on retry, instead of being stranded once the local row exists',
        () async {
      // Other feeds' prior successful syncs already advanced the watermark
      // well past this (about to be newly-subscribed-elsewhere) feed's
      // already-rendered back catalog.
      await db.into(db.syncState).insertOnConflictUpdate(
            SyncStateCompanion.insert(
              id: const Value(0),
              articlesRenderedThrough: const Value('2026-06-01T00:00:00Z'),
            ),
          );

      // Pass 1 — mirrors syncNow: _syncFeeds sees a feed not yet known
      // locally and marks the flag via syncFeedRows.
      await syncFeedRows(db, [
        {'id': 'feed-1', 'url': 'https://example.com/feed', 'title': null},
      ]);
      expect(await hasPendingFullFetch(db), isTrue);

      final failingService = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async => [
          _articleRow(id: 'old-a', renderedAt: '2026-01-01T00:00:00Z', storagePath: 'old-a.zip'),
        ],
        downloadArticleZip: (_) async => throw StateError('network failure'),
      );
      // Mirrors syncNow: forceFullFetch is read from the persisted flag,
      // and clearPendingFullFetch is only reached on the line after this
      // call — which never runs here, since syncArticles throws.
      await expectLater(
        failingService.syncArticles(forceFullFetch: await hasPendingFullFetch(db)),
        throwsStateError,
      );

      // Pass 2 — the feed row now exists locally (syncFeedRows upserted it
      // in pass 1 regardless of the article download failure), so a fresh
      // "is this feed new" comparison would no longer see it as new. That
      // was the bug: the persisted flag from pass 1 must be what survives
      // here instead.
      await syncFeedRows(db, [
        {'id': 'feed-1', 'url': 'https://example.com/feed', 'title': null},
      ]);
      final pendingFullFetch = await hasPendingFullFetch(db);
      expect(pendingFullFetch, isTrue, reason: 'the failed pass must not have lost the retry signal');

      String? requestedSince = 'not called';
      final retryService = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async {
          requestedSince = since;
          return [];
        },
        downloadArticleZip: (_) async => throw StateError('unused'),
      );
      await retryService.syncArticles(forceFullFetch: pendingFullFetch);

      expect(requestedSince, isNull,
          reason: 'the back catalog must still be retried with an unwatermarked fetch, not '
              'silently scoped to the pre-existing watermark');
    });
```

- [ ] **Step 6: Run the sync test file and confirm this test currently passes**

Run: `cd mobile && flutter test test/sync_service_test.dart`
Expected: PASS. (It exercises `syncFeedRows`, already implemented in Step 3 — this step is
confirmatory, not a new RED state. The important RED/GREEN cycle already happened in Steps 1–4;
this test's value is as a regression guard reproducing the original two-pass failure mode, which
you can confirm by temporarily reverting Step 3's `_syncFeeds`/`syncNow` changes and re-running
this single test — it fails with `requestedSince` equal to `'2026-06-01T00:00:00Z'` instead of
`null` against the old code. Re-apply Step 3 afterward.)

- [ ] **Step 7: Run the full mobile test suite and analyzer**

Run: `cd mobile && flutter test && flutter analyze`
Expected: PASS with no new analyzer warnings.

- [ ] **Step 8: Commit**

```bash
git add mobile/lib/features/sync/sync_service.dart mobile/test/sync_service_test.dart
git commit -m "Give cross-device feed subscriptions a durable full-fetch retry signal

_syncFeeds detected a newly-subscribed-elsewhere feed by comparing
against LocalFeeds, but wrote the local row in the same pass before
syncArticles ran — so a failed forced fetch left no signal to retry
from next time, permanently stranding pre-watermark articles for that
feed. syncFeedRows now marks the same persisted needsFullFetch flag
FeedRepository.subscribe already uses, before the local row write."
```

---

### Task 2: Close the same gap in `FeedRepository.subscribe`, and update docs/TODO

**Files:**
- Modify: `mobile/lib/data/remote/feed_repository.dart`
- Modify: `mobile/lib/data/local/database.dart`
- Modify: `TODO.md`

**Interfaces:**
- Consumes: `markPendingFullFetch` (already imported in `feed_repository.dart`; no import changes).
- Produces: nothing new — this task only reorders two existing calls and updates comments/docs.

`FeedRepository.subscribe` has the identical ordering gap Task 1 just fixed in `syncFeedRows`: it
writes the local `LocalFeeds` row *before* calling `markPendingFullFetch`. If the process died
between those two calls, the feed would look "already known" locally with the flag never set —
same stranding bug, different call site. This task is a two-line reorder, not new logic, so it has
no new automated test (this file's static `AppSupabase.client` calls make it untestable the same
way `syncNow`/`_syncFeeds` are — see the Global Constraints note); verified instead by the
analyzer/full suite in Step 3 plus a manual read-through in Step 1.

- [ ] **Step 1: Reorder `subscribe`'s two local writes**

In `mobile/lib/data/remote/feed_repository.dart`, replace:

```dart
    await db.into(db.localFeeds).insertOnConflictUpdate(
          LocalFeedsCompanion.insert(id: feedId, url: url),
        );

    // This write lands before the next sync pass ever compares local feed
    // rows, so SyncService's own newly-subscribed-elsewhere detection would
    // never catch this (re)subscription — mark it explicitly instead. See
    // markPendingFullFetch's doc comment.
    await markPendingFullFetch(db);
```

with:

```dart
    // Mark before writing the local row below, not after: SyncService's
    // own newly-subscribed-elsewhere detection (syncFeedRows) treats a
    // feed as "already known" the moment its LocalFeeds row exists, so if
    // the process died between these two calls in the old order, the flag
    // would never get set and this back catalog would be stranded exactly
    // like the bug this ordering fixes on the other detection path — see
    // docs/superpowers/specs/2026-08-02-force-full-fetch-retry-fix-design.md.
    await markPendingFullFetch(db);

    await db.into(db.localFeeds).insertOnConflictUpdate(
          LocalFeedsCompanion.insert(id: feedId, url: url),
        );
```

- [ ] **Step 2: Update `SyncState.needsFullFetch`'s doc comment**

In `mobile/lib/data/local/database.dart`, replace the `needsFullFetch` column's doc comment:

```dart
  /// Set by [FeedRepository.subscribe] whenever this device (re)subscribes
  /// to a feed, since that write happens synchronously before the next
  /// sync pass — which means the feed is already present in [LocalFeeds]
  /// by the time [SyncService]'s own "is this a new subscription" check
  /// runs, so that check alone would never catch it. Consumed and cleared
  /// by [SyncService.syncNow] once a full-catalog fetch has completed.
```

with:

```dart
  /// Set whenever a feed subscription might have an already-rendered back
  /// catalog this device hasn't pulled yet: by [FeedRepository.subscribe]
  /// when this device does the subscribing, or by `SyncService`'s
  /// `syncFeedRows` when a subscription made on a *different* device first
  /// shows up here. Both call sites mark this before writing the
  /// corresponding [LocalFeeds] row, since once that row exists there's no
  /// other way to detect the feed was ever newly-subscribed. Consumed and
  /// cleared by [SyncService.syncNow] only once a full-catalog fetch has
  /// completed without failing — a failed pass leaves it set so the next
  /// pass retries.
```

- [ ] **Step 3: Run the full mobile test suite and analyzer**

Run: `cd mobile && flutter test && flutter analyze`
Expected: PASS with no new analyzer warnings. (`feed_repository.dart` has no dedicated test file —
this run only confirms nothing else regressed and the file still compiles.)

- [ ] **Step 4: Close the TODO.md item**

In `TODO.md`, remove this line from the "MVP — remaining" section (the fix in this plan closes
both paths that fed it — `FeedRepository.subscribe` via Task 2, `_syncFeeds` via Task 1):

```markdown
- [ ] **A failure during a `forceFullFetch` pass can permanently strand a newly-subscribed feed's back catalog.** `syncNow` (`sync_service.dart`) passes `forceFullFetch: true` exactly once, on the pass a new subscription is detected, to bypass the watermark and pick up that feed's already-rendered older articles. If any row in that one-shot full fetch fails, `syncArticles` withholds the watermark write (correct — see the per-article-failure-isolation comment above it), but on the *next* pass `_syncFeeds` no longer reports the subscription as new (it's already in `localFeeds`), so `syncNow` won't pass `forceFullFetch` again — the failed back-catalog row is never retried. Pre-existing behavior (the old code had the same all-or-nothing outcome via an uncaught exception aborting the pass before the watermark write), not introduced by the per-article isolation work. Needs `forceFullFetch` to be re-derived from "is there a locally-subscribed feed with no synced articles yet" rather than a one-shot flag, or some other durable signal that survives past the single pass.
```

Leave the "MVP — remaining" heading and its remaining item (iOS background fetch config) in place.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/data/remote/feed_repository.dart mobile/lib/data/local/database.dart TODO.md
git commit -m "Close the same forceFullFetch retry-signal gap in FeedRepository.subscribe

subscribe() wrote its local feed row before marking needsFullFetch —
same ordering bug syncFeedRows just fixed on the other detection path.
Swapped the order so the flag survives a crash between the two calls.
Closes TODO.md's forceFullFetch-strand MVP item."
```

---

## Self-Review Notes

- **Spec coverage:** Design doc's "One signal, set at the point of detection" section → Task 1.
  "Ordering is the crux of the fix, twice over" (both bullets) → Task 1 Step 3 (`syncFeedRows`
  ordering) and Task 2 Step 1 (`FeedRepository.subscribe` ordering). "Testing" section's three
  bullets → Task 1 Steps 1 and 5. Non-goals (retroactive rescue, `syncNow`/`_syncFeeds` staying
  untestable directly) are respected — no task attempts either.
- **Placeholder scan:** no TBD/"add error handling"/"similar to Task N" — every step has literal
  code or an exact `git commit` message.
- **Type consistency:** `syncFeedRows(AppDatabase db, List<Map<String, dynamic>> feeds)` is defined
  once in Task 1 Step 3 and called identically (positional args, same map shape) in Task 1 Steps 1,
  3, and 5, and matches `_syncFeeds`'s existing Supabase row shape (`feeds(id, url, title)`).
