import asyncio
import logging
import time
from datetime import UTC, datetime, timedelta
from typing import cast

import feedparser
import httpx
from supabase import Client

from .config import Settings
from .db import rows

logger = logging.getLogger(__name__)


async def poll_due_feeds(db: Client, settings: Settings, http: httpx.AsyncClient) -> None:
    """One pass over feeds whose poll interval has elapsed: fetch the feed
    XML, diff against known articles, and insert `pending` rows for
    anything new. Rendering itself happens separately in the renderer loop.
    """
    cutoff = (datetime.now(UTC) - timedelta(seconds=settings.poll_interval_seconds)).isoformat()
    due = (
        db.table("feeds")
        .select("id, url")
        .or_(f"last_polled_at.is.null,last_polled_at.lt.{cutoff}")
        .execute()
    )

    for feed in rows(due.data):
        try:
            await _poll_one_feed(db, http, feed["id"], feed["url"])
        except Exception:
            logger.exception("Failed polling feed %s (%s)", feed["id"], feed["url"])


async def _poll_one_feed(db: Client, http: httpx.AsyncClient, feed_id: str, feed_url: str) -> None:
    response = await http.get(feed_url, timeout=30, follow_redirects=True)
    response.raise_for_status()

    parsed = await asyncio.to_thread(feedparser.parse, response.content)

    for entry in parsed.entries:
        canonical_url = entry.get("link")
        if not canonical_url:
            continue

        existing = (
            db.table("articles").select("id").eq("canonical_url", canonical_url).limit(1).execute()
        )
        if existing.data:
            continue

        db.table("articles").insert(
            {
                "feed_id": feed_id,
                "canonical_url": canonical_url,
                "status": "pending",
                "title": entry.get("title"),
                "summary": entry.get("summary"),
                "published_at": _entry_published_at(entry),
            }
        ).execute()

    db.table("feeds").update({"last_polled_at": datetime.now(UTC).isoformat()}).eq(
        "id", feed_id
    ).execute()


def _entry_published_at(entry: feedparser.FeedParserDict) -> str | None:
    published_parsed = getattr(entry, "published_parsed", None)
    if published_parsed is None:
        return None
    # feedparser ships no type stubs, so published_parsed is seen as Any —
    # cast to the real runtime type (a 9-field struct_time) so unpacking its
    # first 6 fields into datetime()'s positional args doesn't read as an
    # unbounded-length tuple that could collide with the tzinfo kwarg.
    parsed = cast(time.struct_time, published_parsed)
    return datetime(*parsed[:6], tzinfo=UTC).isoformat()
