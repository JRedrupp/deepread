import asyncio
import logging
from datetime import UTC, datetime

import httpx
from playwright.async_api import Browser
from playwright.async_api import TimeoutError as PlaywrightTimeoutError
from supabase import Client

from .config import Settings
from .packaging import package_article, sanitize
from .paywall import looks_paywalled
from .robots import is_allowed

logger = logging.getLogger(__name__)

USER_AGENT = "deepread-renderer/0.1 (+https://github.com/deepread; offline reading cache)"

with open(__file__.rsplit("/", 1)[0] + "/vendor/Readability.js", encoding="utf-8") as f:
    _READABILITY_JS = f.read()


async def render_pending_articles(
    db: Client, settings: Settings, browser: Browser, http: httpx.AsyncClient
) -> None:
    pending = (
        db.table("articles")
        .select("id, canonical_url, retry_count")
        .eq("status", "pending")
        .limit(settings.render_concurrency * 4)
        .execute()
    )
    if not pending.data:
        return

    semaphore = asyncio.Semaphore(settings.render_concurrency)

    async def _bounded(article: dict) -> None:
        async with semaphore:
            await _render_one(db, settings, browser, http, article)

    await asyncio.gather(*(_bounded(a) for a in pending.data))


async def _render_one(
    db: Client, settings: Settings, browser: Browser, http: httpx.AsyncClient, article: dict
) -> None:
    article_id = article["id"]
    url = article["canonical_url"]

    # Optimistic claim: only proceed if this row is still `pending`. This
    # is what keeps two worker replicas from rendering the same article
    # twice — without it, `render_pending_articles` selecting the same
    # `pending` rows on both machines would double-render every article.
    claim = (
        db.table("articles")
        .update({"status": "rendering"})
        .eq("id", article_id)
        .eq("status", "pending")
        .execute()
    )
    if not claim.data:
        return

    try:
        if not await is_allowed(url, user_agent=USER_AGENT, http=http):
            db.table("articles").update(
                {"status": "failed", "failure_reason": "robots_disallowed"}
            ).eq("id", article_id).execute()
            return

        result = await _render_with_playwright(browser, url)

        if looks_paywalled(
            final_url=result["final_url"], original_url=url, rendered_text=result["text"]
        ):
            # storage_path stays null — the poller already captured the
            # RSS-provided `summary` for this row, which is all the client
            # can offer offline for a paywalled article.
            db.table("articles").update(
                {"status": "ready", "is_paywalled": True, "rendered_at": _now()}
            ).eq("id", article_id).execute()
            return

        sanitized = sanitize(result["content_html"])
        zip_bytes = await package_article(
            html=sanitized, page_url=result["final_url"], title=result["title"], http=http
        )

        storage_path = f"{article_id}.zip"
        db.storage.from_(settings.storage_bucket).upload(
            storage_path, zip_bytes, {"content-type": "application/zip", "upsert": "true"}
        )

        db.table("articles").update(
            {
                "status": "ready",
                "title": result["title"] or None,
                "byline": result["byline"],
                "storage_path": storage_path,
                "rendered_at": _now(),
                "is_paywalled": False,
            }
        ).eq("id", article_id).execute()

    except Exception:
        logger.exception("Render failed for article %s (%s)", article_id, url)
        await _mark_retry_or_failed(db, settings, article)


async def _render_with_playwright(browser: Browser, url: str) -> dict:
    context = await browser.new_context(user_agent=USER_AGENT)
    page = await context.new_page()
    try:
        try:
            await page.goto(url, wait_until="networkidle", timeout=15_000)
        except PlaywrightTimeoutError:
            # Some sites never go fully idle (polling, websockets, ads) —
            # fall back to a fixed settle time after DOM load. This is a
            # known heuristic limitation, see TECH_DEBT.md.
            await page.goto(url, wait_until="domcontentloaded", timeout=15_000)
            await page.wait_for_timeout(2_000)

        text = await page.inner_text("body")
        await page.add_script_tag(content=_READABILITY_JS)
        extracted = await page.evaluate(
            """() => {
                const article = new Readability(document.cloneNode(true)).parse();
                return article ? {
                    title: article.title,
                    byline: article.byline,
                    content: article.content,
                } : null;
            }"""
        )
        if extracted is None:
            raise RuntimeError("Readability could not parse this page")

        return {
            "final_url": page.url,
            "title": extracted["title"],
            "byline": extracted["byline"],
            "content_html": extracted["content"],
            "text": text,
        }
    finally:
        await context.close()


async def _mark_retry_or_failed(db: Client, settings: Settings, article: dict) -> None:
    retry_count = article["retry_count"] + 1
    if retry_count >= settings.render_max_retries:
        db.table("articles").update(
            {"status": "failed", "retry_count": retry_count, "failure_reason": "max_retries"}
        ).eq("id", article["id"]).execute()
    else:
        db.table("articles").update({"retry_count": retry_count}).eq(
            "id", article["id"]
        ).execute()


def _now() -> str:
    return datetime.now(UTC).isoformat()
