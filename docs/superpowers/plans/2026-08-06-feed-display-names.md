# Feed Display Names Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Populate `feeds.title` from each feed's own RSS/Atom `<title>` at poll time, so the
mobile app's existing `title ?? url` fallback shows a real feed name instead of the raw URL.

**Architecture:** One pure helper function (`_feed_title`) computes a stripped, non-empty title
(or `None`) from a parsed feed's metadata. `_poll_one_feed` conditionally includes that title in
the `feeds` row update it already performs every poll — no new DB call, no schema change (`feeds.
title` already exists), no mobile changes (already reads and displays it).

**Tech Stack:** Python 3.12, `feedparser` (already a dependency), `pytest` + `pytest-asyncio`
(`asyncio_mode = "auto"` in `backend/pyproject.toml`), `httpx.MockTransport` for HTTP fakes.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-06-feed-display-names-design.md`.
- Backend-only change. No mobile code changes (mobile already syncs and displays `title`).
- No schema migration and no backfill script — existing feeds self-heal via their normal poll
  cadence (see spec's "Existing feeds / no backfill" section).
- Always overwrite `feeds.title` with the latest non-empty parsed title on every poll (no
  "only-if-null" guard) — a future per-user override will live in `user_feed_subscriptions`, not
  `feeds`, so there's no clobber risk.
- A blank/whitespace-only parsed title must be omitted from the update payload entirely (never
  write `""` or `None` over an existing value).
- Follow this codebase's existing test conventions exactly: hand-rolled fake/recording Supabase
  clients (see `backend/tests/test_renderer.py`'s `_RecordingClient`/`_FakeTable`), and
  `httpx.MockTransport` + real `httpx.AsyncClient` for HTTP fakes (see `backend/tests/
  test_robots.py`). No mocking framework.

---

### Task 1: Populate `feeds.title` from RSS metadata in the poller

**Files:**
- Modify: `backend/deepread_worker/poller.py` (add `_feed_title`; modify `_poll_one_feed`'s
  final `feeds` update at lines 65-67)
- Modify: `TODO.md:15` (the "User-settable feed names" item)
- Test: `backend/tests/test_poller.py` (new file)

**Interfaces:**
- Produces: `_feed_title(feed: feedparser.FeedParserDict) -> str | None` in
  `deepread_worker/poller.py` — pure function, no I/O. Returns the feed's `title` value stripped
  of surrounding whitespace, or `None` if the title is missing, empty, or whitespace-only.

- [ ] **Step 1: Write failing unit tests for `_feed_title`**

Create `backend/tests/test_poller.py` with the pure-function tests first:

```python
from deepread_worker.poller import _feed_title


def test_feed_title_strips_whitespace():
    assert _feed_title({"title": "  Example Feed  "}) == "Example Feed"


def test_feed_title_returns_none_when_key_missing():
    assert _feed_title({}) is None


def test_feed_title_returns_none_when_blank():
    assert _feed_title({"title": "   "}) is None


def test_feed_title_returns_none_when_empty_string():
    assert _feed_title({"title": ""}) is None
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && . .venv/bin/activate && python -m pytest tests/test_poller.py -v`
Expected: FAIL — `ImportError: cannot import name '_feed_title' from 'deepread_worker.poller'`

- [ ] **Step 3: Implement `_feed_title`**

In `backend/deepread_worker/poller.py`, add this function after `_entry_published_at` (end of
file):

```python
def _feed_title(feed: feedparser.FeedParserDict) -> str | None:
    """Feed-level <title>, stripped. None (never an empty string) if the
    feed has no title or only whitespace — the caller uses that to omit
    `title` from the update payload entirely, rather than overwriting a
    previously-set value with blank."""
    title = feed.get("title")
    if title is None:
        return None
    stripped = title.strip()
    return stripped or None
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && . .venv/bin/activate && python -m pytest tests/test_poller.py -v`
Expected: 4 passed

- [ ] **Step 5: Write a failing integration test for the "has a title" case**

Append to `backend/tests/test_poller.py` (add these imports at the top of the file alongside the
existing one: `from types import SimpleNamespace`, `import httpx`, `import pytest`, and
`from deepread_worker.poller import _feed_title, _poll_one_feed`):

```python
_FEED_WITH_TITLE = b"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Feed Title From RSS</title>
    <link>https://example.test/</link>
    <description>Test feed</description>
  </channel>
</rss>
"""

_FEED_WITHOUT_TITLE = b"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <link>https://example-no-title.test/</link>
    <description>Test feed with no title element</description>
  </channel>
</rss>
"""


class _RecordingClient:
    """Hand-rolled stub recording call order — matches this suite's existing
    style (see test_renderer.py's _RecordingClient) of exercising real code
    paths rather than mocking Supabase."""

    def __init__(self) -> None:
        self.calls: list[tuple] = []

    def table(self, name: str) -> "_FakeTable":
        return _FakeTable(self, name)


class _FakeTable:
    def __init__(self, client: "_RecordingClient", name: str) -> None:
        self._client = client
        self._name = name
        self._payload: dict | None = None

    def update(self, payload: dict) -> "_FakeTable":
        self._payload = payload
        return self

    def eq(self, column: str, value) -> "_FakeTable":
        return self

    def execute(self):
        self._client.calls.append(("table_update", self._name, self._payload))
        return SimpleNamespace(data=[])


@pytest.mark.asyncio
async def test_poll_one_feed_writes_title_parsed_from_rss():
    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=_FEED_WITH_TITLE)

    transport = httpx.MockTransport(handler)
    client = _RecordingClient()

    async with httpx.AsyncClient(transport=transport) as http:
        await _poll_one_feed(client, http, "feed-1", "https://example.test/feed.xml")

    assert len(client.calls) == 1
    _, table_name, payload = client.calls[0]
    assert table_name == "feeds"
    assert payload["title"] == "Feed Title From RSS"
    assert "last_polled_at" in payload
```

- [ ] **Step 6: Run the new test to verify it fails**

Run: `cd backend && . .venv/bin/activate && python -m pytest tests/test_poller.py -k writes_title -v`
Expected: FAIL — `KeyError: 'title'` (current `_poll_one_feed` only writes `last_polled_at`)

- [ ] **Step 7: Wire `_feed_title` into `_poll_one_feed`'s update call**

In `backend/deepread_worker/poller.py`, replace the final block of `_poll_one_feed` (currently
lines 65-67):

```python
    db.table("feeds").update({"last_polled_at": datetime.now(UTC).isoformat()}).eq(
        "id", feed_id
    ).execute()
```

with:

```python
    update_payload: dict[str, str] = {"last_polled_at": datetime.now(UTC).isoformat()}
    title = _feed_title(parsed.feed)
    if title is not None:
        update_payload["title"] = title

    db.table("feeds").update(update_payload).eq("id", feed_id).execute()
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `cd backend && . .venv/bin/activate && python -m pytest tests/test_poller.py -k writes_title -v`
Expected: PASS

- [ ] **Step 9: Write a test for the "no title in the feed" case**

Append to `backend/tests/test_poller.py`:

```python
@pytest.mark.asyncio
async def test_poll_one_feed_omits_title_when_feed_has_none():
    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=_FEED_WITHOUT_TITLE)

    transport = httpx.MockTransport(handler)
    client = _RecordingClient()

    async with httpx.AsyncClient(transport=transport) as http:
        await _poll_one_feed(client, http, "feed-2", "https://example-no-title.test/feed.xml")

    assert len(client.calls) == 1
    _, table_name, payload = client.calls[0]
    assert table_name == "feeds"
    assert "title" not in payload
    assert "last_polled_at" in payload
```

- [ ] **Step 10: Run all tests in the file to verify everything passes**

Run: `cd backend && . .venv/bin/activate && python -m pytest tests/test_poller.py -v`
Expected: 6 passed

- [ ] **Step 11: Update the TODO.md entry to reflect the reduced remaining scope**

In `TODO.md`, replace line 15 (the "User-settable feed names" item):

```markdown
- [ ] User-settable feed names. Feeds currently show their raw URL as the display name (`feed.title ?? feed.url` in `FeedListScreen`, and `feeds.title` is never actually populated server-side) — let the user rename a feed to something readable. The combined all-articles view's per-article feed badge (`ArticleListTile`) now makes this gap more visible too, since it falls back to the raw feed URL there as well — worth fixing together.
```

with:

```markdown
- [ ] User-settable feed names (per-user override). `feeds.title` is now populated from the feed's own RSS/Atom `<title>` at poll time (`deepread_worker.poller._feed_title`), so `feed.title ?? feed.url` in `FeedListScreen`/`ArticleListTile`/etc. shows the feed's real name in the common case instead of falling back to the raw URL. What's still missing is a **per-user** rename — letting one subscriber call a feed something different from its RSS-provided name, without affecting other subscribers of the same shared `feeds` row. That needs its own storage scoped to `user_feed_subscriptions` (not `feeds`, which is global) plus display-priority logic (override → RSS title → URL). See `docs/superpowers/specs/2026-08-06-feed-display-names-design.md` for why the two are split.
```

- [ ] **Step 12: Run the full backend test suite**

Run: `cd backend && . .venv/bin/activate && python -m pytest`
Expected: all tests pass, no regressions in other suites (`test_cleanup.py`, `test_packaging.py`,
`test_paywall.py`, `test_renderer.py`, `test_robots.py`)

- [ ] **Step 13: Commit**

```bash
git add backend/deepread_worker/poller.py backend/tests/test_poller.py TODO.md
git commit -m "Populate feeds.title from RSS metadata at poll time"
```
