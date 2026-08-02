# Stuck `rendering` rows sweep — design

## Problem

The renderer's claim mechanism (`deepread_worker.renderer._render_one`) flips an article from
`status='pending'` to `status='rendering'` via a conditional update, used as an optimistic lock so
two worker replicas can't render the same article twice. Nothing ever reverts that transition
except a successful (or exception-caught) completion of the same render call:

1. **Process crash mid-render** (OOM, container kill, unhandled signal) leaves the row in
   `rendering` forever — nothing observes the abandoned claim.
2. **Caught, non-max-retry exceptions have the same bug today.** `_mark_retry_or_failed`'s `else`
   branch (retry budget not yet exhausted) only increments `retry_count`; it never resets `status`
   back to `pending`. So a transient failure we *do* catch — a network blip, a Playwright timeout
   — also strands the row in `rendering`, identical to case 1, just for a different reason.

Both are silent: the article never renders, never fails visibly, and blocks nothing else, so
there's no error signal an operator would notice. `TECH_DEBT.md` documents case 1; investigation
for this design confirmed case 2 is the same underlying gap, just reached without a crash.

## Goal

Add a durable signal for how long a row has been claimed, and a periodic sweep that reclaims a
claim that's gone stale — while also closing case 2 directly, since we already know about that
failure the moment it happens and shouldn't make it wait on a periodic sweep.

Out of scope:
- A dedicated job queue (Redis, etc.) — `TECH_DEBT.md`'s broader "no dedicated job queue" note is
  unchanged; this only fixes reclaim of a single worker process's own abandoned claims.
- Alerting/visibility into *why* a row went stale — same `TECH_DEBT.md` gap as failed-render
  dead-lettering generally; out of scope here.

## Design

### Schema: `articles.claimed_at`

New migration `supabase/migrations/0005_articles_claimed_at.sql`:

```sql
alter table articles add column claimed_at timestamptz;
```

Nullable, no default. Only ever written by the claim itself; never explicitly cleared when a row
leaves `rendering` — every read of it is always paired with `status='rendering'`, so a stale value
on a `ready`/`failed`/`pending` row is inert.

### `renderer.py`: set `claimed_at` at claim time, fix the non-max-retry gap

`_render_one`'s claim update:

```python
claim = (
    db.table("articles")
    .update({"status": "rendering", "claimed_at": _now()})
    .eq("id", article_id)
    .eq("status", "pending")
    .execute()
)
```

`_mark_retry_or_failed`'s `else` branch, closing case 2 directly rather than deferring to the
sweep:

```python
else:
    db.table("articles").update(
        {"status": "pending", "retry_count": retry_count}
    ).eq("id", article["id"]).execute()
```

### `config.py`: new tunable

```python
stale_claim_minutes: int = 30
```

wired through a `STALE_CLAIM_MINUTES` env var, following the same pattern as
`article_retention_days`/`orphan_grace_period_hours` — an operator can tune it without a redeploy.
30 minutes is generous headroom: a single render (Playwright nav + Readability + packaging +
upload) normally completes in low tens of seconds.

### `cleanup.py`: a fourth phase in `run_cleanup_pass`

Mirrors the existing pure-decision / thin-I/O-wrapper split already used for the retention and
hard-delete tiers:

```python
def build_stale_claim_filter(cutoff: datetime) -> str:
    """Nulls-included: a row claimed before this column existed (or by a claim
    update that itself failed to persist claimed_at) must count as stale
    immediately, not survive forever unreclaimed."""
    return f"claimed_at.is.null,claimed_at.lt.{cutoff.isoformat()}"


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

A stale reclaim counts as a retry attempt (increments `retry_count`, same as a caught exception
would), so a URL that reliably crashes or hangs the renderer still converges to `failed` instead of
looping through claim → stale → reclaim indefinitely.

`run_cleanup_pass` gains a corresponding unconditional block (this tier has no on/off env flag,
unlike `orphan_sweep_enabled` — reclaiming abandoned claims isn't optional the way the orphan sweep
is):

```python
candidates = await asyncio.to_thread(list_stale_claims, db, settings)
if candidates:
    await asyncio.to_thread(reclaim_stale_claims, db, settings, candidates)
```

Also wired into `main()`'s `--dry-run` branch, printing count + ids, matching the existing two
tiers' dry-run output.

### Release ordering

`release.yml` runs `supabase db push` before `flyctl deploy` in the same job, so the nullable
`claimed_at` column is always live before the backend code that reads/writes it — this ships in one
release, no phased rollout needed. The `OR claimed_at IS NULL` clause above means any row already
stuck in `rendering` from *before* this deploy (which by definition has no `claimed_at`) gets picked
up and reclaimed on the very first cleanup pass afterward — self-healing, no backfill migration or
manual SQL required.

### Testing

`tests/test_cleanup.py`, following the existing style (pure decision functions tested directly,
no live Supabase needed):

- `build_stale_claim_filter`'s exact filter string for a given cutoff, the same way
  `build_expired_or_filter` is already tested.
- `reclaim_stale_claims`'s branch logic extracted as pure candidate-plus-settings → intended update
  mapping (mirrors `filter_zip_candidates`'s style), tested for both branches:
  - `retry_count + 1 < render_max_retries` → `status='pending'`, `claimed_at=None`, incremented
    `retry_count`.
  - `retry_count + 1 >= render_max_retries` → `status='failed'`, `failure_reason='stale_claim_max_retries'`.

`tests/test_renderer.py`:

- `_mark_retry_or_failed`'s non-max-retry branch now asserts the update payload includes
  `status: "pending"` (previously only `retry_count`) — this is the regression test for case 2;
  run against current code it fails (payload omits `status`), passes once fixed.
- `_render_one`'s claim update includes a `claimed_at` key (exact value not asserted, just
  presence) in the successful-claim path.
