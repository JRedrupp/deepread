# Sync pagination fix — design

## Problem

`SyncService.syncArticles` (`mobile/lib/features/sync/sync_service.dart`) fetches all
newly-ready/re-rendered articles in a single unpaginated query. Supabase's PostgREST layer
silently caps any query at `max_rows` (`supabase/config.toml`, currently `1000`) — if a sync pass
(most commonly a large first sync, or a newly-subscribed feed's `forceFullFetch` back-catalog
pull) has more than 1000 matching rows, only the first 1000 come back.

Because `syncArticles` advances its local watermark (`syncState.articlesRenderedThrough`) to the
max `rendered_at` seen in *that* response, a truncated page's watermark still advances — past the
point where the un-fetched remainder lives. Those rows are then permanently invisible to every
future pass, since `since` (`.gt('rendered_at', since)`) starts after them. This is silent,
permanent article loss, not a transient failure that self-heals on retry.

## Goal

Make one `syncArticles()` call traverse the *entire* backlog matching its `since` window,
regardless of size, while preserving the file's existing failure-isolation guarantee: the
persisted watermark only advances once every row in the pass — now potentially spanning multiple
pages — has been handled without error.

Out of scope: `forceFullFetch`'s own retry-signal gap (TODO.md's third MVP item) — same file,
different root cause, tracked separately.

## Design

### Core loop

Wrap the existing single-fetch-then-process body in `syncArticles` in an outer loop. The Supabase
query gains `.order('rendered_at').limit(pageSize)`.

Two variables must stay distinct — this is the crux of the fix:

- **`fetchCursor`** — drives `since` for the *next page fetch only*. Advances to the last row's
  `rendered_at` at the end of every page, unconditionally, even if some rows in that page failed
  to process. Without this, a mid-page failure would leave the pass re-fetching the same page
  forever instead of reaching the rest of the backlog.
- **`newWatermark`** — the value actually persisted to `articlesRenderedThrough`. Unchanged
  per-row semantics (only advances on a row that processed successfully), but now accumulated
  across *all* pages in the pass, and gated on `failureCount == 0` computed across the *whole*
  pass — not per page. A failure on page 4 of 5 means nothing commits; the next call safely
  re-fetches the same starting window (already-handled rows just hit `ArticleSyncAction.skip`
  again, which is cheap).

A page shorter than `pageSize` means the backlog is exhausted — loop stops. No separate count
query needed.

**Crash/kill safety:** if the process (particularly the background `WorkManager` isolate, which
has OS-imposed execution time limits) is killed mid-pass, nothing corrupts. Rows already
downloaded are already written to local storage with their `renderedAt`. Since the watermark only
commits after the full multi-page pass completes, the next pass re-fetches from the same starting
point — already-handled rows skip cheaply. This falls out of the existing design; no new code
needed for it, just worth a comment at the point where the watermark write happens.

### Interface changes

- `_defaultFetchReadyArticles` gains a `required int limit` param, applies `.limit(limit)`.
- The `fetchReadyArticles` field type on `SyncService` changes from
  `Future<List<Map<String, dynamic>>> Function({String? since})` to
  `Future<List<Map<String, dynamic>>> Function({String? since, required int limit})`.
  Every test-injected closure for this field needs the param added (mechanical; most ignore it).
- `SyncService` gains a `pageSize` constructor field, defaulting to `1000` (matching
  `supabase/config.toml`'s `max_rows`). Not an I/O seam like the file's other injected
  dependencies — a plain int — but without it, testing the multi-page loop boundary would need
  1000+-row literal fixtures per test. Injectable, tests use small values (e.g. `2`).

### Testing (`mobile/test/sync_service_test.dart`)

New tests, using a small injected `pageSize`:

- A pass spanning exactly 2 pages advances the watermark to the true max across both pages, and
  only after both are fully processed (i.e., fetch is called twice).
- A failure on page 1 still allows page 2 to be fetched (proves `fetchCursor` diverges from
  `newWatermark` on failure) — but the watermark does not advance at all.
- A failure on page 2 (after page 1's rows all succeeded) still leaves the watermark unadvanced —
  proves the whole-pass gate, not a per-page one.
- A page returning fewer rows than `pageSize` stops the loop — no extra fetch call is made.

Existing single-page tests are updated only for the `fetchReadyArticles` signature change
(add/ignore `limit`); their behavior is unchanged, since a single page under `pageSize` is the
same code path as before, not a special case.

## Non-goals / accepted risk

- **Exact-timestamp ties at a page boundary.** `rendered_at` is a Postgres `timestamptz` set once
  per row via a single `now()` call at render completion. Two different articles landing on the
  byte-identical microsecond value — such that a keyset cursor could skip one of them — is
  considered practically unobservable given real-world render timing, even under
  `render_concurrency > 1`. Documented as an accepted edge case in a code comment rather than
  adding a compound `(rendered_at, id)` cursor with dedup tracking.
- **`forceFullFetch`'s retry-signal gap** (TODO.md) is explicitly out of scope for this change.
