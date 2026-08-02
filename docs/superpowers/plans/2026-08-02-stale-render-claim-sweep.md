# Stale Render-Claim Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reclaim `articles` rows stuck in `status='rendering'` — whether from a crashed worker process or a caught-but-unrecorded transient failure — so they eventually retry or fail instead of sitting invisibly stuck forever.

**Architecture:** Add a `claimed_at` timestamp column set at claim time; fix a second, already-present bug where a caught non-max-retry render exception forgets to revert `status` to `pending`; add a fourth cleanup phase (`deepread_worker.cleanup`) that finds `rendering` rows whose claim is older than a configurable threshold (or has no `claimed_at` at all — pre-dating this column) and resets them to `pending` or `failed` depending on remaining retry budget.

**Tech Stack:** Python 3.12, `supabase-py`, `pytest` + `pytest-asyncio`, plain SQL migrations (Supabase).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-02-stuck-rendering-rows-sweep-design.md` — this plan implements it exactly; do not add scope beyond it.
- All backend commands run from `backend/` with the venv active: `cd backend && . .venv/bin/activate && ...`.
- New migration file: `supabase/migrations/0005_articles_claimed_at.sql` (next number after `0004_cleanup_support.sql`).
- New config tunable: `stale_claim_minutes: int = 30`, wired through `STALE_CLAIM_MINUTES` env var, following the exact pattern of the other cleanup tunables in `backend/deepread_worker/config.py`.
- Follow this repo's existing test style: pure decision functions tested directly with plain asserts; I/O-touching functions tested against small hand-rolled recording fakes (see `_RecordingClient`/`_FakeTable` in `backend/tests/test_cleanup.py`) — no mocking framework.
- Branch `feature/stale-render-claim-sweep` already exists and is checked out; commit directly to it (no new branch needed).

---

### Task 1: Migration — add `articles.claimed_at`

**Files:**
- Create: `supabase/migrations/0005_articles_claimed_at.sql`

**Interfaces:**
- Consumes: nothing.
- Produces: `articles.claimed_at timestamptz` (nullable, no default) — consumed by Task 2 (write) and Task 4 (read).

- [ ] **Step 1: Write the migration file**

```sql
-- Set at render-claim time (deepread_worker.renderer._render_one) so the
-- cleanup sweep (deepread_worker.cleanup) can detect a claim that's gone
-- stale (crashed worker, or a transient failure that never got recorded)
-- and reclaim the row back to pending/failed instead of leaving it stuck
-- in 'rendering' forever.
alter table articles add column claimed_at timestamptz;
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/0005_articles_claimed_at.sql
git commit -m "Add articles.claimed_at column for render-claim reclaim"
```

---

### Task 2: `renderer.py` — set `claimed_at` at claim time, fix the non-max-retry status bug

**Files:**
- Modify: `backend/deepread_worker/renderer.py:61-67` (the claim update in `_render_one`)
- Modify: `backend/deepread_worker/renderer.py:160-167` (`_mark_retry_or_failed`)
- Test: `backend/tests/test_renderer.py`

**Interfaces:**
- Consumes: `Settings.render_max_retries` (existing field, unchanged), the file's existing `_now() -> str` helper (`renderer.py:170-171`).
- Produces: the claim update payload now includes `"claimed_at"`; `_mark_retry_or_failed`'s non-max-retry branch now sets `"status": "pending"` in addition to `"retry_count"`.

- [ ] **Step 1: Write the failing tests**

Add to `backend/tests/test_renderer.py`. First, merge the new imports into the existing import block at the top of the file:

```python
from types import SimpleNamespace

import pytest
from playwright.async_api import async_playwright

from deepread_worker.config import Settings
from deepread_worker.renderer import _mark_retry_or_failed, _render_one, _render_with_playwright
```

Then append this recording-fake helper and the two new tests to the end of the file:

```python
class _RecordingClient:
    """Hand-rolled stub recording call order — no mocking framework, matching
    test_cleanup.py's style of exercising real code paths directly rather
    than mocking Supabase."""

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
async def test_render_one_claim_includes_claimed_at():
    # claim.execute() returns data=[] (simulating a lost claim race), so
    # _render_one returns immediately after the claim call — this isolates
    # the claim payload without needing to stub browser/http/robots/etc.
    client = _RecordingClient()
    settings = Settings(supabase_url="http://x", supabase_service_role_key="key")
    article = {"id": "abc-123", "canonical_url": "http://example.com", "retry_count": 0}

    await _render_one(client, settings, browser=None, http=None, article=article)

    assert len(client.calls) == 1
    _, table_name, payload = client.calls[0]
    assert table_name == "articles"
    assert payload["status"] == "rendering"
    assert "claimed_at" in payload


@pytest.mark.asyncio
async def test_mark_retry_or_failed_resets_status_to_pending_when_retries_remain():
    client = _RecordingClient()
    settings = Settings(
        supabase_url="http://x", supabase_service_role_key="key", render_max_retries=3
    )
    article = {"id": "abc-123", "retry_count": 0}

    await _mark_retry_or_failed(client, settings, article)

    assert client.calls == [
        ("table_update", "articles", {"status": "pending", "retry_count": 1})
    ]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && . .venv/bin/activate && python -m pytest tests/test_renderer.py -k "claim_includes_claimed_at or resets_status_to_pending" -v`

Expected: both FAIL — the first because the claim payload has no `claimed_at` key, the second because the actual payload is `{"retry_count": 1}` with no `status` key.

- [ ] **Step 3: Implement the fix**

In `backend/deepread_worker/renderer.py`, change the claim update (currently lines 61-67):

```python
    claim = (
        db.table("articles")
        .update({"status": "rendering", "claimed_at": _now()})
        .eq("id", article_id)
        .eq("status", "pending")
        .execute()
    )
```

And change `_mark_retry_or_failed`'s `else` branch (currently lines 166-167):

```python
    else:
        db.table("articles").update(
            {"status": "pending", "retry_count": retry_count}
        ).eq("id", article["id"]).execute()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && . .venv/bin/activate && python -m pytest tests/test_renderer.py -v`

Expected: all PASS, including the pre-existing `test_render_succeeds_under_strict_csp`.

- [ ] **Step 5: Commit**

```bash
git add backend/deepread_worker/renderer.py backend/tests/test_renderer.py
git commit -m "Set claimed_at on render claim; reset status to pending on transient failure"
```

---

### Task 3: `config.py` — add `stale_claim_minutes` tunable

**Files:**
- Modify: `backend/deepread_worker/config.py`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Settings.stale_claim_minutes: int` (default `30`), populated from `STALE_CLAIM_MINUTES` env var in `Settings.from_env()` — consumed by Task 4.

No dedicated test: none of the other tunables in this file (`article_retention_days`, `orphan_grace_period_hours`, etc.) have direct unit tests either — `Settings` is a plain dataclass with no logic to test in isolation. Step 3 below (running the full suite) is the verification.

- [ ] **Step 1: Add the field**

In `backend/deepread_worker/config.py`, add to the `Settings` dataclass, directly below `orphan_grace_period_hours` (currently line 30):

```python
    # How long a row can sit in status='rendering' before the cleanup sweep
    # assumes the claiming process died (or lost the claim mid-render without
    # recording it) and reclaims the row. See deepread_worker.cleanup.
    stale_claim_minutes: int = 30
```

- [ ] **Step 2: Wire it through `from_env`**

Add to the `from_env` classmethod's return, directly below `orphan_grace_period_hours=...` (currently line 58):

```python
            stale_claim_minutes=cls._env_int("STALE_CLAIM_MINUTES", 30),
```

- [ ] **Step 3: Run the full backend test suite to confirm nothing broke**

Run: `cd backend && . .venv/bin/activate && python -m pytest`

Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add backend/deepread_worker/config.py
git commit -m "Add stale_claim_minutes tunable"
```

---

### Task 4: `cleanup.py` — stale-claim sweep, wired into `run_cleanup_pass` and `--dry-run`

**Files:**
- Modify: `backend/deepread_worker/cleanup.py`
- Test: `backend/tests/test_cleanup.py`

**Interfaces:**
- Consumes: `Settings.stale_claim_minutes` (Task 3), `Settings.render_max_retries` and `Settings.cleanup_batch_size` (existing fields).
- Produces: `build_stale_claim_filter(cutoff: datetime) -> str`, `list_stale_claims(db: Client, settings: Settings) -> list[dict]`, `reclaim_stale_claims(db: Client, settings: Settings, candidates: list[dict]) -> None`. `run_cleanup_pass` and `main()`'s `--dry-run` branch both call these unconditionally (this tier has no on/off flag, unlike `orphan_sweep_enabled`).

- [ ] **Step 1: Write the failing tests**

Add `build_stale_claim_filter`, `list_stale_claims`, and `reclaim_stale_claims` to the existing import block at the top of `backend/tests/test_cleanup.py`:

```python
from deepread_worker.cleanup import (
    build_expired_or_filter,
    build_stale_claim_filter,
    compute_cutoff,
    expire_articles,
    filter_hard_delete_candidates,
    filter_zip_candidates,
    find_orphan_objects,
    has_suspicious_empty_live_set,
    is_managed_object_name,
    list_live_storage_paths,
    reclaim_stale_claims,
)
```

Add an `eq` method to the existing `_FakeTable` class (`backend/tests/test_cleanup.py:124-139`), directly below its `in_` method, so it can record the per-row `.eq("id", ...)` calls `reclaim_stale_claims` makes (the existing `expire_articles`/`hard_delete_articles` tests only exercise the batched `.in_()` path):

```python
    def eq(self, column: str, value) -> "_FakeTable":
        return self
```

Append these three tests to the end of the file:

```python
def test_build_stale_claim_filter_format():
    cutoff = datetime(2026, 1, 1, tzinfo=UTC)
    cutoff_iso = cutoff.isoformat()
    assert build_stale_claim_filter(cutoff) == f"claimed_at.is.null,claimed_at.lt.{cutoff_iso}"


def test_reclaim_stale_claims_resets_to_pending_when_retries_remain():
    client = _RecordingClient()
    settings = Settings(
        supabase_url="http://x", supabase_service_role_key="key", render_max_retries=3
    )
    candidates = [{"id": "abc", "retry_count": 0}]

    reclaim_stale_claims(client, settings, candidates)

    assert client.calls == [
        ("table_update", "articles", {"status": "pending", "retry_count": 1, "claimed_at": None})
    ]


def test_reclaim_stale_claims_fails_when_retries_exhausted():
    client = _RecordingClient()
    settings = Settings(
        supabase_url="http://x", supabase_service_role_key="key", render_max_retries=1
    )
    candidates = [{"id": "abc", "retry_count": 0}]

    reclaim_stale_claims(client, settings, candidates)

    assert client.calls == [
        (
            "table_update",
            "articles",
            {"status": "failed", "retry_count": 1, "failure_reason": "stale_claim_max_retries"},
        )
    ]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && . .venv/bin/activate && python -m pytest tests/test_cleanup.py -k "stale_claim" -v`

Expected: FAIL with `ImportError` (`build_stale_claim_filter`/`reclaim_stale_claims` don't exist yet).

- [ ] **Step 3: Implement `build_stale_claim_filter` and `list_stale_claims`**

In `backend/deepread_worker/cleanup.py`, add directly below `build_expired_or_filter` (currently ends at line 58, before `filter_zip_candidates`):

```python
def build_stale_claim_filter(cutoff: datetime) -> str:
    """Nulls-included: a row claimed before this column existed (or by a claim
    update that itself failed to persist claimed_at) must count as stale
    immediately, not survive forever unreclaimed."""
    return f"claimed_at.is.null,claimed_at.lt.{cutoff.isoformat()}"
```

Add `list_stale_claims` in the "thin Supabase I/O wrappers" section, directly below `list_hard_delete_candidates` (currently ends at line 148, before `hard_delete_articles`):

```python
def list_stale_claims(db: Client, settings: Settings) -> list[dict]:
    cutoff = datetime.now(UTC) - timedelta(minutes=settings.stale_claim_minutes)
    result = (
        db.table("articles")
        .select("id, retry_count")
        .eq("status", "rendering")
        .or_(build_stale_claim_filter(cutoff))
        .limit(settings.cleanup_batch_size)
        .execute()
    )
    return rows(result.data)
```

- [ ] **Step 4: Implement `reclaim_stale_claims`**

Add directly below `list_stale_claims`:

```python
def reclaim_stale_claims(db: Client, settings: Settings, candidates: list[dict]) -> None:
    for c in candidates:
        retry_count = c["retry_count"] + 1
        if retry_count >= settings.render_max_retries:
            db.table("articles").update(
                {
                    "status": "failed",
                    "retry_count": retry_count,
                    "failure_reason": "stale_claim_max_retries",
                }
            ).eq("id", c["id"]).execute()
        else:
            db.table("articles").update(
                {"status": "pending", "retry_count": retry_count, "claimed_at": None}
            ).eq("id", c["id"]).execute()
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd backend && . .venv/bin/activate && python -m pytest tests/test_cleanup.py -v`

Expected: all PASS, including every pre-existing test in the file.

- [ ] **Step 6: Wire the new phase into `run_cleanup_pass`**

In `backend/deepread_worker/cleanup.py`, add a fourth block to `run_cleanup_pass` (currently lines 227-251), after the `orphan_sweep_enabled` block, before the function ends:

```python
    stale_claims = await asyncio.to_thread(list_stale_claims, db, settings)
    if stale_claims:
        await asyncio.to_thread(reclaim_stale_claims, db, settings, stale_claims)
```

This block is unconditional (no settings flag gating it), unlike `orphan_sweep_enabled` — reclaiming abandoned claims isn't optional the way the orphan sweep is.

- [ ] **Step 7: Wire the new phase into the `--dry-run` CLI branch**

In `backend/deepread_worker/cleanup.py`'s `main()` function, add directly below the `orphan_sweep_enabled` dry-run block (currently ends at line 296, before the function ends):

```python
    stale_claims = list_stale_claims(db, settings)
    print(f"Would reclaim {len(stale_claims)} stale 'rendering' claim(s)")
    for c in stale_claims[:20]:
        print(f"  {c['id']}  retry_count={c['retry_count']}")
```

- [ ] **Step 8: Run the full backend test suite**

Run: `cd backend && . .venv/bin/activate && python -m pytest`

Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add backend/deepread_worker/cleanup.py backend/tests/test_cleanup.py
git commit -m "Add stale render-claim reclaim sweep to cleanup pass"
```

---

## Self-Review Notes

- **Spec coverage:** migration (Task 1) → §"Schema"; renderer claim + `_mark_retry_or_failed` fix (Task 2) → §"renderer.py"; `stale_claim_minutes` tunable (Task 3) → §"config.py"; sweep functions + wiring + dry-run (Task 4) → §"cleanup.py". Release-ordering and null-handling behavior from the spec are structural properties of this implementation (migration-before-deploy is a `release.yml` fact, not new code; `OR claimed_at IS NULL` is `build_stale_claim_filter`'s exact behavior) — no separate task needed.
- **Type consistency:** `reclaim_stale_claims` takes `candidates: list[dict]` with `id`/`retry_count` keys, matching exactly what `list_stale_claims`'s `.select("id, retry_count")` returns. `Settings.stale_claim_minutes` (Task 3) is the exact name `list_stale_claims` (Task 4) reads.
