import httpx
import pytest

from deepread_worker import robots


@pytest.mark.asyncio
async def test_missing_robots_txt_is_cached_not_refetched_every_call():
    request_count = 0

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal request_count
        request_count += 1
        return httpx.Response(404)

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as http:
        for _ in range(5):
            allowed = await robots.is_allowed(
                "https://no-robots-example.test/article-1",
                user_agent="test-agent",
                http=http,
            )
            assert allowed is True

    assert request_count == 1, (
        "expected robots.txt to be fetched once and cached, "
        f"but it was fetched {request_count} times"
    )


@pytest.mark.asyncio
async def test_disallowed_path_is_rejected():
    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, text="User-agent: *\nDisallow: /private/\n")

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as http:
        allowed = await robots.is_allowed(
            "https://example-disallow.test/private/secret",
            user_agent="test-agent",
            http=http,
        )
        assert allowed is False
