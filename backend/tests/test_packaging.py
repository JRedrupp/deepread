import io
import zipfile

import httpx
import pytest

from deepread_worker.packaging import package_article, sanitize


def test_sanitize_strips_scripts_and_event_handlers():
    dirty = '<p onclick="evil()">hello</p><script>evil()</script>'
    clean = sanitize(dirty)
    assert "<script>" not in clean
    assert "onclick" not in clean
    assert "hello" in clean


def test_sanitize_keeps_allowed_tags():
    clean = sanitize("<h1>Title</h1><p>Body <a href='https://x.com'>link</a></p>")
    assert "<h1>" in clean
    assert 'href="https://x.com"' in clean
    assert "<a " in clean and "link</a>" in clean


@pytest.mark.asyncio
async def test_package_article_downloads_and_rewrites_images():
    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=b"fake-image-bytes")

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as http:
        zip_bytes = await package_article(
            html='<p>hi</p><img src="photo.jpg">',
            page_url="https://example.com/article",
            title="Test Article",
            http=http,
        )

    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as archive:
        names = archive.namelist()
        assert "index.html" in names
        image_names = [n for n in names if n.startswith("images/")]
        assert len(image_names) == 1

        index_html = archive.read("index.html").decode()
        assert image_names[0] in index_html
        assert "photo.jpg" not in index_html.split(f'src="{image_names[0]}"')[0]
