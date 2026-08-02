from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

from deepread_worker.cleanup import (
    build_expired_or_filter,
    build_stale_claim_filter,
    compute_cutoff,
    expire_articles,
    filter_hard_delete_candidates,
    filter_zip_candidates,
    find_orphan_objects,
    has_suspicious_empty_live_set,
    is_managed_object_name,
    list_live_storage_paths,
    reclaim_stale_claims,
)
from deepread_worker.config import Settings

_UUID = "1a2b3c4d-5e6f-4a1b-8c2d-9e0f1a2b3c4d"


def test_compute_cutoff():
    now = datetime(2026, 8, 1, tzinfo=UTC)
    assert compute_cutoff(now, 180) == now - timedelta(days=180)


def test_build_expired_or_filter_format():
    cutoff = datetime(2026, 1, 1, tzinfo=UTC)
    cutoff_iso = cutoff.isoformat()
    assert build_expired_or_filter(cutoff) == (
        f"published_at.lt.{cutoff_iso},and(published_at.is.null,created_at.lt.{cutoff_iso})"
    )


def test_filter_zip_candidates_filters_missing_storage_path():
    rows = [
        {"id": "1", "storage_path": "1.zip"},
        {"id": "2", "storage_path": None},
    ]
    assert filter_zip_candidates(rows) == [{"id": "1", "storage_path": "1.zip"}]


def test_filter_hard_delete_candidates_keeps_only_nulled_rows():
    rows = [
        {"id": "1", "storage_path": "1.zip"},
        {"id": "2", "storage_path": None},
    ]
    assert filter_hard_delete_candidates(rows) == [{"id": "2", "storage_path": None}]


def test_is_managed_object_name_accepts_uuid_zip():
    assert is_managed_object_name(f"{_UUID}.zip")


def test_is_managed_object_name_rejects_unmanaged_names():
    assert not is_managed_object_name(".emptyFolderPlaceholder")
    assert not is_managed_object_name(".zip")
    assert not is_managed_object_name("not-a-uuid.zip")
    assert not is_managed_object_name(f"sub/{_UUID}.zip")


def test_find_orphan_objects_skips_live_paths():
    name = f"{_UUID}.zip"
    old = (datetime.now(UTC) - timedelta(days=1)).isoformat()
    objects = [{"name": name, "created_at": old}]
    orphans = find_orphan_objects(
        objects, live_storage_paths={name}, grace_cutoff=datetime.now(UTC)
    )
    assert orphans == []


def test_find_orphan_objects_respects_grace_period():
    name = f"{_UUID}.zip"
    grace_cutoff = datetime(2026, 1, 1, tzinfo=UTC)

    just_under = {"name": name, "created_at": (grace_cutoff + timedelta(hours=1)).isoformat()}
    assert find_orphan_objects([just_under], set(), grace_cutoff) == []

    just_over = {"name": name, "created_at": (grace_cutoff - timedelta(hours=1)).isoformat()}
    assert find_orphan_objects([just_over], set(), grace_cutoff) == [name]

    missing_created_at = {"name": name}
    assert find_orphan_objects([missing_created_at], set(), grace_cutoff) == []


def test_find_orphan_objects_ignores_unmanaged_names():
    old = (datetime.now(UTC) - timedelta(days=365)).isoformat()
    objects = [{"name": ".emptyFolderPlaceholder", "created_at": old}]
    assert find_orphan_objects(objects, set(), datetime.now(UTC)) == []


def test_find_orphan_objects_handles_real_storage_wire_format():
    # Supabase Storage returns Z-suffixed UTC timestamps, not +00:00.
    name = f"{_UUID}.zip"
    objects = [{"name": name, "created_at": "2020-01-01T00:00:00.000Z"}]
    assert find_orphan_objects(objects, set(), datetime.now(UTC)) == [name]


def test_has_suspicious_empty_live_set_flags_query_failure():
    objects = [{"name": f"{_UUID}.zip"}]
    assert has_suspicious_empty_live_set(objects, set()) is True


def test_has_suspicious_empty_live_set_allows_genuinely_empty_bucket():
    assert has_suspicious_empty_live_set([], set()) is False


def test_has_suspicious_empty_live_set_ignores_unmanaged_objects():
    objects = [{"name": ".emptyFolderPlaceholder"}]
    assert has_suspicious_empty_live_set(objects, set()) is False


class _RecordingClient:
    """Hand-rolled stub recording call order — no mocking framework, matching
    this suite's existing style of exercising real code paths directly rather
    than mocking Supabase."""

    def __init__(self) -> None:
        self.calls: list[tuple] = []
        self.storage = SimpleNamespace(from_=lambda bucket: _FakeBucket(self, bucket))

    def table(self, name: str) -> "_FakeTable":
        return _FakeTable(self, name)


class _FakeTable:
    def __init__(self, client: _RecordingClient, name: str) -> None:
        self._client = client
        self._name = name
        self._payload: dict | None = None

    def update(self, payload: dict) -> "_FakeTable":
        self._payload = payload
        return self

    def in_(self, column: str, values: list) -> "_FakeTable":
        return self

    def eq(self, column: str, value) -> "_FakeTable":
        return self

    def execute(self):
        self._client.calls.append(("table_update", self._name, self._payload))
        return SimpleNamespace(data=[])


class _FakeBucket:
    def __init__(self, client: _RecordingClient, bucket: str) -> None:
        self._client = client
        self._bucket = bucket

    def remove(self, paths: list[str]):
        self._client.calls.append(("storage_remove", self._bucket, paths))
        return []


def test_expire_articles_updates_row_before_removing_storage_object():
    client = _RecordingClient()
    settings = Settings(supabase_url="http://x", supabase_service_role_key="key")
    candidates = [{"id": "abc", "storage_path": "abc.zip"}]

    expire_articles(client, settings, candidates)

    assert [call[0] for call in client.calls] == ["table_update", "storage_remove"]
    assert client.calls[0][2] == {"storage_path": None}
    assert client.calls[1][2] == ["abc.zip"]


class _PagedArticlesClient:
    """Fake client for the list_live_storage_paths pagination test: serves
    `storage_paths` back in pages, exercising the .range() loop the same way
    a PostgREST row cap would in production."""

    def __init__(self, storage_paths: list[str]) -> None:
        self._paths = storage_paths

    def table(self, name: str) -> "_PagedArticlesTable":
        return _PagedArticlesTable(self._paths)


class _PagedArticlesTable:
    def __init__(self, paths: list[str]) -> None:
        self._paths = paths
        self._start = 0
        self._end = 0

    def select(self, *_args, **_kwargs) -> "_PagedArticlesTable":
        return self

    @property
    def not_(self) -> "_PagedArticlesTable":
        return self

    def is_(self, *_args, **_kwargs) -> "_PagedArticlesTable":
        return self

    def range(self, start: int, end: int) -> "_PagedArticlesTable":
        self._start, self._end = start, end
        return self

    def execute(self):
        page = self._paths[self._start : self._end + 1]
        return SimpleNamespace(data=[{"storage_path": p} for p in page])


def test_list_live_storage_paths_does_not_truncate_beyond_one_page():
    paths = [f"{i}.zip" for i in range(5)]
    client = _PagedArticlesClient(paths)
    settings = Settings(supabase_url="http://x", supabase_service_role_key="key")

    result = list_live_storage_paths(client, settings, page_size=2)

    assert result == set(paths)


def test_build_stale_claim_filter_format():
    cutoff = datetime(2026, 1, 1, tzinfo=UTC)
    cutoff_iso = cutoff.isoformat()
    assert build_stale_claim_filter(cutoff) == f"claimed_at.is.null,claimed_at.lt.{cutoff_iso}"


def test_reclaim_stale_claims_resets_to_pending_when_retries_remain():
    client = _RecordingClient()
    settings = Settings(
        supabase_url="http://x", supabase_service_role_key="key", render_max_retries=3
    )
    candidates = [{"id": "abc", "retry_count": 0}]

    reclaim_stale_claims(client, settings, candidates)

    assert client.calls == [
        ("table_update", "articles", {"status": "pending", "retry_count": 1, "claimed_at": None})
    ]


def test_reclaim_stale_claims_fails_when_retries_exhausted():
    client = _RecordingClient()
    settings = Settings(
        supabase_url="http://x", supabase_service_role_key="key", render_max_retries=1
    )
    candidates = [{"id": "abc", "retry_count": 0}]

    reclaim_stale_claims(client, settings, candidates)

    assert client.calls == [
        (
            "table_update",
            "articles",
            {"status": "failed", "retry_count": 1, "failure_reason": "stale_claim_max_retries"},
        )
    ]
