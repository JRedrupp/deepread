import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
from playwright.async_api import async_playwright

from deepread_worker.renderer import _render_with_playwright

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
