"""Render a single real URL through the actual render pipeline, no Supabase
required — for debugging site-specific render failures locally.

    python -m deepread_worker.debug_render <url>
"""

import argparse
import asyncio
import hashlib
import logging
from pathlib import Path

import httpx
from playwright.async_api import async_playwright

from .packaging import package_article, sanitize
from .paywall import looks_paywalled
from .renderer import USER_AGENT, _render_with_playwright
from .robots import is_allowed

logging.basicConfig(level=logging.INFO)

OUTPUT_DIR = Path(__file__).resolve().parent.parent / "render-output"


async def _run(url: str) -> None:
    async with async_playwright() as playwright, httpx.AsyncClient() as http:
        if not await is_allowed(url, user_agent=USER_AGENT, http=http):
            print("robots.txt disallows this URL for our user agent — not rendering.")
            return

        browser = await playwright.chromium.launch()
        try:
            result = await _render_with_playwright(browser, url)
        finally:
            await browser.close()

        print(f"final_url: {result['final_url']}")
        print(f"title:     {result['title']!r}")
        print(f"byline:    {result['byline']!r}")
        print(f"text:      {len(result['text'])} chars extracted")
        print(f"content:   {len(result['content_html'])} chars of HTML")

        paywalled = looks_paywalled(
            final_url=result["final_url"], original_url=url, rendered_text=result["text"]
        )
        print(f"paywalled: {paywalled}")
        if paywalled:
            return

        sanitized = sanitize(result["content_html"])
        zip_bytes = await package_article(
            html=sanitized, page_url=result["final_url"], title=result["title"], http=http
        )

        OUTPUT_DIR.mkdir(exist_ok=True)
        slug = hashlib.sha1(url.encode()).hexdigest()[:16]
        out_path = OUTPUT_DIR / f"{slug}.zip"
        out_path.write_bytes(zip_bytes)
        print(f"wrote:     {out_path} ({len(zip_bytes)} bytes)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", help="URL to render")
    args = parser.parse_args()
    asyncio.run(_run(args.url))


if __name__ == "__main__":
    main()
