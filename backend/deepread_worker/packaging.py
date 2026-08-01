"""Turns Readability's extracted HTML into a self-contained offline package:
sanitized HTML with images downloaded and rewritten to local relative paths,
zipped together as `index.html` + `images/`.
"""

import hashlib
import io
import zipfile
from urllib.parse import urljoin

import httpx
import nh3

_ALLOWED_TAGS = {
    "p",
    "div",
    "span",
    "br",
    "hr",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "ul",
    "ol",
    "li",
    "a",
    "img",
    "figure",
    "figcaption",
    "blockquote",
    "pre",
    "code",
    "em",
    "strong",
    "b",
    "i",
    "u",
    "s",
    "table",
    "thead",
    "tbody",
    "tr",
    "th",
    "td",
}
_ALLOWED_ATTRIBUTES = {
    "a": {"href", "title"},
    "img": {"src", "alt", "title"},
}

# Matches the Flutter client's dev-tool dark theme (see mobile/lib/theme/app_theme.dart)
# so an article doesn't jar against the surrounding app chrome. Readability's
# output has no styling of its own — without this, a WebView renders raw
# browser defaults (unstyled bullet lists, blue underlined links, images
# wider than the screen).
_ARTICLE_CSS = """
  body {
    background: #10151C;
    color: #E6E8EB;
    font-family: -apple-system, Roboto, Helvetica, Arial, sans-serif;
    line-height: 1.6;
    margin: 0;
    padding: 20px 16px 48px;
    max-width: 700px;
  }
  h1, h2, h3, h4, h5, h6 { line-height: 1.3; color: #E6E8EB; }
  img { max-width: 100%; height: auto; display: block; margin: 12px 0; border-radius: 6px; }
  a { color: #4FD1B5; }
  blockquote {
    margin: 16px 0; padding: 4px 16px;
    border-left: 3px solid #262E3A; color: #8A94A3;
  }
  pre, code {
    font-family: 'JetBrains Mono', 'Fira Code', monospace;
    background: #161C25; border-radius: 4px;
  }
  pre { padding: 12px; overflow-x: auto; }
  code { padding: 2px 4px; }
  table { border-collapse: collapse; width: 100%; }
  th, td { border: 1px solid #262E3A; padding: 8px; text-align: left; }
"""


def sanitize(raw_html: str) -> str:
    """Strips scripts, event handlers, and anything not in the allow-list —
    defense in depth on top of Readability already dropping most cruft.
    """
    return nh3.clean(raw_html, tags=_ALLOWED_TAGS, attributes=_ALLOWED_ATTRIBUTES)


async def package_article(
    *, html: str, page_url: str, title: str, http: httpx.AsyncClient
) -> bytes:
    """Downloads every <img> referenced in `html`, rewrites src to a local
    `images/<hash>.<ext>` path, and returns a zip archive (bytes) containing
    `index.html` plus the downloaded images.
    """
    import re

    images: dict[str, str] = {}  # original src -> local path

    def _local_name(src: str) -> str:
        if src not in images:
            digest = hashlib.sha1(src.encode()).hexdigest()[:16]
            ext = src.rsplit(".", 1)[-1].lower() if "." in src.rsplit("/", 1)[-1] else "jpg"
            ext = ext if len(ext) <= 4 else "jpg"
            images[src] = f"images/{digest}.{ext}"
        return images[src]

    def _rewrite(match: re.Match) -> str:
        original_src = match.group(1)
        absolute_src = urljoin(page_url, original_src)
        local = _local_name(absolute_src)
        return f'src="{local}"'

    rewritten_html = re.sub(r'src="([^"]+)"', _rewrite, html)

    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "index.html",
            f"<!doctype html><html><head><meta charset='utf-8'>"
            f'<meta name="viewport" content="width=device-width, initial-scale=1">'
            f"<title>{title}</title><style>{_ARTICLE_CSS}</style></head>"
            f"<body>{rewritten_html}</body></html>",
        )
        for original_src, local_path in images.items():
            try:
                response = await http.get(original_src, timeout=15)
                response.raise_for_status()
                archive.writestr(local_path, response.content)
            except httpx.HTTPError:
                continue  # a missing image shouldn't fail the whole article

    return buffer.getvalue()
