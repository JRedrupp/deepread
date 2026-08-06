from types import SimpleNamespace

import httpx
import pytest

from deepread_worker.poller import _feed_title, _poll_one_feed


def test_feed_title_strips_whitespace():
    assert _feed_title({"title": "  Example Feed  "}) == "Example Feed"


def test_feed_title_returns_none_when_key_missing():
    assert _feed_title({}) is None


def test_feed_title_returns_none_when_blank():
    assert _feed_title({"title": "   "}) is None


def test_feed_title_returns_none_when_empty_string():
    assert _feed_title({"title": ""}) is None


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
