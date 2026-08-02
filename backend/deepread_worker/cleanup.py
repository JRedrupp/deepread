"""Server-side maintenance pass for the shared `articles` cache and its Storage bucket.

Four phases, run periodically by `_cleanup_loop` in main.py, or once via:

    python -m deepread_worker.cleanup [--dry-run]

The first three are individually gated by settings; the fourth (stale render-claim
reclaim) is unconditional.

1. Tier one (article_retention_days): a `ready` article's rendered zip is removed
   from Storage once it's old enough, and its `storage_path` is set to null. The
   row itself is kept — the article becomes a summary-only entry, identical to a
   paywalled one, from the client's perspective (see sync_service.dart's decision
   on `storagePath == null`). Kept as a tombstone so poller.py's canonical_url
   dedup check still sees it and never re-inserts/re-renders it.
2. Tier two (article_hard_delete_days): once a tombstone (storage_path already
   null) is old enough, the row itself is deleted. Safe at this much longer
   horizon — an entry still listed in its source feed's XML just gets re-rendered
   once, not looped.
3. Orphan sweep: lists the Storage bucket and removes any managed-looking object
   not referenced by any current row's storage_path — self-healing against the
   renderer's upload-before-row-update crash race, a feed-delete FK cascade
   orphaning its articles' objects, or a failed removal in tier one above.
4. Stale render-claim reclaim (list_stale_claims/reclaim_stale_claims): resets
   `rendering` rows whose `claimed_at` is older than stale_claim_minutes (or
   still null) back to `pending`, or to `failed` once retry_count has hit
   render_max_retries. Recovers rows abandoned by a crashed worker or a render
   failure that never got to `_mark_retry_or_failed`. Always runs, unlike the
   phases above — an abandoned claim blocks that article from ever being
   retried, so reclaiming it isn't an optional storage-hygiene policy the way
   the other three are.

Every mutation updates/deletes the row strictly before touching the Storage
object, never after — this is what keeps mobile sync out of a permanent retry
loop (see the plan doc / sync_service.dart's watermark-freezes-on-failure logic).
"""

import argparse
import asyncio
import logging
import re
from datetime import UTC, datetime, timedelta

from dotenv import load_dotenv
from supabase import Client

from .config import Settings
from .db import make_client, rows

logger = logging.getLogger(__name__)

_MANAGED_OBJECT_NAME = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.zip$", re.IGNORECASE
)


# --- pure decision logic (no I/O — directly unit-testable) ---


def compute_cutoff(now: datetime, days: int) -> datetime:
    return now - timedelta(days=days)


def build_expired_or_filter(cutoff: datetime) -> str:
    """Same `.or_()` idiom as poller.py's due-feed query: articles published
    before the cutoff, or with no published_at at all but created before it."""
    cutoff_iso = cutoff.isoformat()
    return f"published_at.lt.{cutoff_iso},and(published_at.is.null,created_at.lt.{cutoff_iso})"


def build_stale_claim_filter(cutoff: datetime) -> str:
    """Nulls-included: a row claimed before this column existed (or by a claim
    update that itself failed to persist claimed_at) must count as stale
    immediately, not survive forever unreclaimed."""
    return f"claimed_at.is.null,claimed_at.lt.{cutoff.isoformat()}"


def filter_zip_candidates(rows: list[dict]) -> list[dict]:
    """Defense-in-depth: only ever act on rows that actually have a storage_path,
    even though the query already filters for `storage_path is not null`."""
    return [r for r in rows if r.get("storage_path")]


def filter_hard_delete_candidates(rows: list[dict]) -> list[dict]:
    """Defense-in-depth mirror of filter_zip_candidates: only ever hard-delete
    rows that are actually already-nulled tombstones."""
    return [r for r in rows if not r.get("storage_path")]


def is_managed_object_name(name: str) -> bool:
    """True only for `{uuid}.zip`, renderer.py's exact naming convention. Guards
    the orphan sweep against ever touching an unrelated bucket entry."""
    return bool(_MANAGED_OBJECT_NAME.match(name))


def find_orphan_objects(
    objects: list[dict], live_storage_paths: set[str], grace_cutoff: datetime
) -> list[str]:
    """Managed-looking object names, older than grace_cutoff, not referenced by
    any current row's storage_path. Objects with a missing/unparseable
    created_at are skipped rather than reaped, to fail safe."""
    orphans = []
    for obj in objects:
        name = obj.get("name", "")
        if not is_managed_object_name(name) or name in live_storage_paths:
            continue
        created_at = obj.get("created_at")
        if not created_at:
            continue
        try:
            created = datetime.fromisoformat(created_at)
        except ValueError:
            continue
        if created < grace_cutoff:
            orphans.append(name)
    return orphans


# --- thin Supabase I/O wrappers ---


def list_expiring_articles(db: Client, settings: Settings) -> list[dict]:
    cutoff = compute_cutoff(datetime.now(UTC), settings.article_retention_days)
    result = (
        db.table("articles")
        .select("id, storage_path")
        .eq("status", "ready")
        .not_.is_("storage_path", "null")
        .or_(build_expired_or_filter(cutoff))
        .limit(settings.cleanup_batch_size)
        .execute()
    )
    return rows(result.data)


def expire_articles(db: Client, settings: Settings, candidates: list[dict]) -> None:
    candidates = filter_zip_candidates(candidates)
    if not candidates:
        return
    ids = [c["id"] for c in candidates]
    paths = [c["storage_path"] for c in candidates]
    # Row update first: once storage_path is null, no client can newly discover
    # this article and attempt to download the object we're about to remove.
    db.table("articles").update({"storage_path": None}).in_("id", ids).execute()
    try:
        db.storage.from_(settings.storage_bucket).remove(paths)
    except Exception:
        logger.exception(
            "Failed to remove %d expired Storage object(s); the orphan sweep will retry them",
            len(paths),
        )


def list_hard_delete_candidates(db: Client, settings: Settings) -> list[dict]:
    cutoff = compute_cutoff(datetime.now(UTC), settings.article_hard_delete_days)
    result = (
        db.table("articles")
        .select("id, storage_path")
        .eq("status", "ready")
        .is_("storage_path", "null")
        .or_(build_expired_or_filter(cutoff))
        .limit(settings.cleanup_batch_size)
        .execute()
    )
    return rows(result.data)


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


def hard_delete_articles(db: Client, settings: Settings, candidates: list[dict]) -> None:
    candidates = filter_hard_delete_candidates(candidates)
    if not candidates:
        return
    ids = [c["id"] for c in candidates]
    db.table("articles").delete().in_("id", ids).execute()


def list_bucket_objects(db: Client, settings: Settings) -> list[dict]:
    """Storage `.list()` defaults to a 100-object page — loop with offset until
    a short page comes back, or only the bucket's alphabetically-first 100
    objects would ever be seen."""
    objects: list[dict] = []
    offset = 0
    page_size = 100
    while True:
        page = db.storage.from_(settings.storage_bucket).list(
            options={"limit": page_size, "offset": offset}
        )
        objects.extend(page)
        if len(page) < page_size:
            break
        offset += page_size
    return objects


_LIVE_PATHS_PAGE_SIZE = 500


def list_live_storage_paths(
    db: Client, settings: Settings, page_size: int = _LIVE_PATHS_PAGE_SIZE
) -> set[str]:
    """Paginated via `.range()` — PostgREST caps rows server-side (this
    project's own supabase/config.toml sets max_rows = 1000; TODO.md notes the
    same truncation hazard already bit mobile sync once). An unpaginated
    select would silently see only the first page once the table passes that
    cap, making the orphan sweep below treat every live object beyond it as
    unreferenced and delete a still-referenced zip."""
    paths: set[str] = set()
    offset = 0
    while True:
        page = (
            db.table("articles")
            .select("storage_path")
            .not_.is_("storage_path", "null")
            .range(offset, offset + page_size - 1)
            .execute()
        )
        page_rows = rows(page.data)
        paths.update(row["storage_path"] for row in page_rows)
        if len(page_rows) < page_size:
            break
        offset += page_size
    return paths


def has_suspicious_empty_live_set(objects: list[dict], live_storage_paths: set[str]) -> bool:
    """True if live_storage_paths came back empty while the bucket has
    managed-looking objects — almost certainly a query failure, not a
    genuinely empty articles table. Callers should skip the orphan sweep
    rather than treat every object in the bucket as unreferenced."""
    if live_storage_paths:
        return False
    return any(is_managed_object_name(obj.get("name", "")) for obj in objects)


def remove_storage_objects(db: Client, settings: Settings, names: list[str]) -> None:
    try:
        db.storage.from_(settings.storage_bucket).remove(names)
    except Exception:
        logger.exception("Failed to remove %d orphaned Storage object(s)", len(names))


# --- orchestration ---


async def run_cleanup_pass(db: Client, settings: Settings) -> None:
    if settings.article_retention_days:
        candidates = await asyncio.to_thread(list_expiring_articles, db, settings)
        if candidates:
            await asyncio.to_thread(expire_articles, db, settings, candidates)

    if settings.article_hard_delete_days:
        candidates = await asyncio.to_thread(list_hard_delete_candidates, db, settings)
        if candidates:
            await asyncio.to_thread(hard_delete_articles, db, settings, candidates)

    if settings.orphan_sweep_enabled:
        objects = await asyncio.to_thread(list_bucket_objects, db, settings)
        live = await asyncio.to_thread(list_live_storage_paths, db, settings)
        if has_suspicious_empty_live_set(objects, live):
            logger.error(
                "Orphan sweep skipped: live_storage_paths came back empty while the "
                "bucket has managed objects -- likely a query failure, not a genuinely "
                "empty articles table"
            )
        else:
            grace_cutoff = datetime.now(UTC) - timedelta(hours=settings.orphan_grace_period_hours)
            orphans = find_orphan_objects(objects, live, grace_cutoff)
            if orphans:
                await asyncio.to_thread(remove_storage_objects, db, settings, orphans)

    stale_claims = await asyncio.to_thread(list_stale_claims, db, settings)
    if stale_claims:
        await asyncio.to_thread(reclaim_stale_claims, db, settings, stale_claims)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run", action="store_true", help="Print candidates without mutating anything"
    )
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    load_dotenv()
    settings = Settings.from_env()
    db = make_client(settings)

    if not args.dry_run:
        asyncio.run(run_cleanup_pass(db, settings))
        return

    if settings.article_retention_days:
        candidates = filter_zip_candidates(list_expiring_articles(db, settings))
        print(f"Would null storage_path + remove zip for {len(candidates)} article(s)")
        for c in candidates[:20]:
            print(f"  {c['id']}  {c['storage_path']}")

    if settings.article_hard_delete_days:
        candidates = filter_hard_delete_candidates(list_hard_delete_candidates(db, settings))
        print(f"Would hard-delete {len(candidates)} tombstone row(s)")
        for c in candidates[:20]:
            print(f"  {c['id']}")

    if settings.orphan_sweep_enabled:
        objects = list_bucket_objects(db, settings)
        live = list_live_storage_paths(db, settings)
        if has_suspicious_empty_live_set(objects, live):
            print(
                "Orphan sweep: live_storage_paths came back empty while the bucket has "
                "managed objects -- skipping (likely a query failure, not a genuinely "
                "empty articles table)"
            )
        else:
            grace_cutoff = datetime.now(UTC) - timedelta(hours=settings.orphan_grace_period_hours)
            orphans = find_orphan_objects(objects, live, grace_cutoff)
            print(f"Would remove {len(orphans)} orphaned Storage object(s)")
            for name in orphans[:20]:
                print(f"  {name}")

    stale_claims = list_stale_claims(db, settings)
    print(f"Would reclaim {len(stale_claims)} stale 'rendering' claim(s)")
    for c in stale_claims[:20]:
        print(f"  {c['id']}  retry_count={c['retry_count']}")


if __name__ == "__main__":
    main()
