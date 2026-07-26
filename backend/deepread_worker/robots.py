import asyncio
from functools import lru_cache
from urllib.parse import urlparse
from urllib.robotparser import RobotFileParser

import httpx


@lru_cache(maxsize=512)
def _parser_for_host(scheme: str, netloc: str) -> RobotFileParser:
    parser = RobotFileParser()
    parser.set_url(f"{scheme}://{netloc}/robots.txt")
    return parser


async def is_allowed(url: str, *, user_agent: str, http: httpx.AsyncClient) -> bool:
    parsed = urlparse(url)
    parser = _parser_for_host(parsed.scheme, parsed.netloc)

    if not parser.mtime():
        try:
            response = await http.get(
                f"{parsed.scheme}://{parsed.netloc}/robots.txt", timeout=10
            )
            if response.status_code == 200:
                await asyncio.to_thread(parser.parse, response.text.splitlines())
            else:
                # No robots.txt (or inaccessible) is treated as allow-all,
                # matching standard crawler convention. `parse([])` still
                # records a cache hit via RobotFileParser.modified(), so we
                # don't refetch this host on every single article.
                await asyncio.to_thread(parser.parse, [])
        except httpx.HTTPError:
            await asyncio.to_thread(parser.parse, [])

    return parser.can_fetch(user_agent, url)
