import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    supabase_url: str
    supabase_service_role_key: str
    storage_bucket: str = "articles"

    poll_interval_seconds: int = 300
    render_concurrency: int = 3
    render_max_retries: int = 3
    render_nav_timeout_ms: int = 15_000

    # --- retention/cleanup (deepread_worker.cleanup) ---
    # Age (from published_at, falling back to created_at) at which a ready article's
    # Storage zip is removed and storage_path is set to null. 0 disables this tier.
    article_retention_days: int = 180
    # Age at which a row whose storage_path is already null gets hard-deleted. Only
    # ever applied to rows past the tier above. 0 disables this tier.
    article_hard_delete_days: int = 730
    cleanup_interval_seconds: int = 21_600
    # Caps rows touched per pass so a large pre-existing backlog bleeds down over
    # several passes instead of one huge update/delete.
    cleanup_batch_size: int = 200
    orphan_sweep_enabled: bool = True
    # Never reap a Storage object younger than this, to avoid racing an in-flight
    # upload for a brand-new article (renderer.py uploads before updating the row).
    orphan_grace_period_hours: int = 24
    # How long a row can sit in status='rendering' before the cleanup sweep
    # assumes the claiming process died (or lost the claim mid-render without
    # recording it) and reclaims the row. See deepread_worker.cleanup.
    stale_claim_minutes: int = 30

    @staticmethod
    def _env_int(name: str, default: int) -> int:
        value = os.environ.get(name)
        return int(value) if value is not None else default

    @staticmethod
    def _env_bool(name: str, default: bool) -> bool:
        value = os.environ.get(name)
        if value is None:
            return default
        return value.strip().lower() not in ("0", "false", "no", "")

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            supabase_url=os.environ["SUPABASE_URL"],
            supabase_service_role_key=os.environ["SUPABASE_SERVICE_ROLE_KEY"],
            # Unlike the tunables above (dataclass-default-only), these are wired
            # through env vars: this is a destructive, irreversible deleter with no
            # undo, so an operator needs to disable/tune it without a redeploy if
            # something looks wrong in production.
            article_retention_days=cls._env_int("ARTICLE_RETENTION_DAYS", 180),
            article_hard_delete_days=cls._env_int("ARTICLE_HARD_DELETE_DAYS", 730),
            cleanup_interval_seconds=cls._env_int("CLEANUP_INTERVAL_SECONDS", 21_600),
            cleanup_batch_size=cls._env_int("CLEANUP_BATCH_SIZE", 200),
            orphan_sweep_enabled=cls._env_bool("ORPHAN_SWEEP_ENABLED", True),
            orphan_grace_period_hours=cls._env_int("ORPHAN_GRACE_PERIOD_HOURS", 24),
            stale_claim_minutes=cls._env_int("STALE_CLAIM_MINUTES", 30),
        )
