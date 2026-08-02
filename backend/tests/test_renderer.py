import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from types import SimpleNamespace

import pytest
from playwright.async_api import async_playwright

from deepread_worker.config import Settings
from deepread_worker.renderer import _mark_retry_or_failed, _render_one, _render_with_playwright

_ARTICLE_HTML = b"""
<!doctype html>
<html>
<head><title>Strict CSP Article</title></head>
<body>
  <article>
    <h1>Strict CSP Article</h1>
    <p>This page enforces a script-src CSP with no 'unsafe-inline', the same as
    GitHub Pages and Discourse forums. It has enough body text for Readability
    to treat it as the page's main content rather than boilerplate.</p>
    <p>A second paragraph keeps Readability's content-scoring heuristics happy,
    since single-paragraph pages are sometimes scored too low to extract.</p>
  </article>
</body>
</html>
"""


class _StrictCspHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Security-Policy", "default-src 'none'; script-src 'self'")
        self.send_header("Content-Length", str(len(_ARTICLE_HTML)))
        self.end_headers()
        self.wfile.write(_ARTICLE_HTML)

    def log_message(self, *args: object) -> None:  # silence test output
        pass


@pytest.fixture
def strict_csp_server():
    server = ThreadingHTTPServer(("127.0.0.1", 0), _StrictCspHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}/"
    finally:
        server.shutdown()
        thread.join()
        server.server_close()


@pytest.mark.asyncio
async def test_render_succeeds_under_strict_csp(strict_csp_server):
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch()
        try:
            result = await _render_with_playwright(browser, strict_csp_server)
        finally:
            await browser.close()

    assert result["title"] == "Strict CSP Article"
    assert "content-scoring heuristics" in result["content_html"]


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
