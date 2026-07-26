from deepread_worker.paywall import looks_paywalled


def test_detects_redirect_to_login_url():
    assert looks_paywalled(
        final_url="https://example.com/login?next=/article",
        original_url="https://example.com/article",
        rendered_text="please sign in",
    )


def test_detects_paywall_text_marker():
    assert looks_paywalled(
        final_url="https://example.com/article",
        original_url="https://example.com/article",
        rendered_text="Subscribe to continue reading this story.",
    )


def test_allows_normal_public_article():
    assert not looks_paywalled(
        final_url="https://example.com/article",
        original_url="https://example.com/article",
        rendered_text="This is a normal public article with plenty of text.",
    )
