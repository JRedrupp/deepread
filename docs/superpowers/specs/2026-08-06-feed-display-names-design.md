# Feed display names (common name from RSS) — design

## Problem

Feeds show their raw URL as the display name everywhere (`FeedListScreen`, `ArticleListScreen`,
the all-articles view's per-article feed badge) because `feeds.title` is never populated
server-side — `backend/deepread_worker/poller.py`'s `_poll_one_feed` already parses each feed's
XML with `feedparser` (which exposes the feed's own `<title>` as `parsed.feed.title`) but never
writes it anywhere. This is a tracked TODO.md item.

Mobile already fully supports a populated title: `SyncService._syncFeeds` selects
`feeds(id, url, title)` and `syncFeedRows` upserts it into `LocalFeeds.title`, and every display
site already falls back to `feed.title ?? feed.url`. The entire gap is the missing server-side
write.

## Scope

This is the **common name** only — the feed's own name, as reported by its RSS/Atom `<title>`,
shared by every subscriber (consistent with `feeds` being a global/shared table — one row per
feed URL, one render cache per article, serving every subscriber). A **per-user custom rename**
(a user overriding what they personally call a feed) is a separate concern that would need its
own storage scoped to `user_feed_subscriptions` (not `feeds`, which can't hold a
per-user value) and its own display-priority logic (override → common name → URL). That stays a
future TODO item, not part of this design.

Because a future per-user override will never live in `feeds.title` itself, there's no future
conflict from always keeping `feeds.title` in sync with the feed's current RSS title.

## Design

### Backend change

In `_poll_one_feed` (`backend/deepread_worker/poller.py`), after `feedparser.parse()` succeeds,
read `parsed.feed.get("title")`, strip whitespace, and — if non-empty — include it as `title` in
the same `feeds` table update call that already unconditionally sets `last_polled_at` at the end
of the function. No extra DB round-trip.

If the parsed title is empty or whitespace-only (malformed/incomplete feed), omit `title` from
the update dict entirely rather than writing an empty string — this leaves whatever's already in
the DB untouched (null on a first poll, or a previously-set value on a later one), so a single bad
poll pass can't blank out a title a prior poll successfully set.

### Overwrite policy

Always write the latest non-empty title on every poll — no "only if currently null" guard. Since
a future per-user override lives elsewhere (see Scope), there's no risk of this clobbering a
user's customization, and it keeps the common name fresh if a feed's own metadata changes (e.g. a
site rebrand).

### Existing feeds / no backfill

No backfill migration or one-off script. Every existing feed already has `last_polled_at` set, so
it's already on its normal poll cadence and will naturally become "due" again and pick up its
title on its next regularly-scheduled poll — self-healing, bounded by `poll_interval_seconds`
(default 5 min, `backend/deepread_worker/config.py`), the same latency class as new-article
delivery already has.

### Error handling

No new failure modes. This rides inside the existing per-feed `try`/`except` in `poll_due_feeds`,
which already logs and continues to the next feed on any exception (network error, malformed XML,
etc.) — a title-parsing hiccup can't take down the whole poll pass.

### Mobile

No changes. `SyncService`/`syncFeedRows` already pulls and stores `title`; every display site
already does `title ?? url`.

### Testing

`backend/tests/` has no `test_poller.py` yet — add one covering:

- A feed with a `<title>` in its XML: the `feeds` update call includes that title.
- A feed with no `<title>` (or an empty/whitespace one): the update call omits `title` entirely
  (doesn't write `""` or `None` over an existing value).
- `last_polled_at` is updated in both cases regardless of title presence.

## Non-goals / accepted scope

- **No per-user custom feed renaming.** Tracked separately in TODO.md; this design deliberately
  doesn't touch `user_feed_subscriptions` or add any rename UI.
- **No backfill script for existing feeds.** Self-healing via normal poll cadence, per above.
- **No change to mobile fallback/display logic.** Already correct; this design only fixes the
  missing write on the backend.
