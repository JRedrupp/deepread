"""Best-effort detection of paywalled/login-gated pages.

This is intentionally conservative: false positives (skipping a page that
was actually public) are cheap, but false negatives (caching content behind
a login wall) are the thing we must not do — see TODO.md's legal gate.
"""

import re

_LOGIN_URL_MARKERS = re.compile(r"(login|signin|sign-in|auth/|paywall)", re.IGNORECASE)

_PAYWALL_TEXT_MARKERS = (
    "subscribe to continue reading",
    "this content is for subscribers",
    "you've reached your free article limit",
    "create a free account to continue",
    "sign in to continue reading",
)


def looks_paywalled(*, final_url: str, original_url: str, rendered_text: str) -> bool:
    if final_url != original_url and _LOGIN_URL_MARKERS.search(final_url):
        return True

    haystack = rendered_text.lower()
    return any(marker in haystack for marker in _PAYWALL_TEXT_MARKERS)
