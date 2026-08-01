import asyncio
import logging

import httpx
from dotenv import load_dotenv
from playwright.async_api import async_playwright

from .cleanup import run_cleanup_pass
from .config import Settings
from .db import make_client
from .poller import poll_due_feeds
from .renderer import render_pending_articles

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def _poller_loop(settings: Settings) -> None:
    db = make_client(settings)
    async with httpx.AsyncClient() as http:
        while True:
            try:
                await poll_due_feeds(db, settings, http)
            except Exception:
                logger.exception("Poller loop iteration failed")
            await asyncio.sleep(settings.poll_interval_seconds)


async def _renderer_loop(settings: Settings) -> None:
    db = make_client(settings)
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch()
        try:
            async with httpx.AsyncClient() as http:
                while True:
                    try:
                        await render_pending_articles(db, settings, browser, http)
                    except Exception:
                        logger.exception("Renderer loop iteration failed")
                    await asyncio.sleep(10)
        finally:
            await browser.close()


async def _cleanup_loop(settings: Settings) -> None:
    db = make_client(settings)
    while True:
        try:
            await run_cleanup_pass(db, settings)
        except Exception:
            logger.exception("Cleanup loop iteration failed")
        await asyncio.sleep(settings.cleanup_interval_seconds)


async def main() -> None:
    load_dotenv()
    settings = Settings.from_env()
    await asyncio.gather(_poller_loop(settings), _renderer_loop(settings), _cleanup_loop(settings))


if __name__ == "__main__":
    asyncio.run(main())
