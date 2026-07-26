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

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            supabase_url=os.environ["SUPABASE_URL"],
            supabase_service_role_key=os.environ["SUPABASE_SERVICE_ROLE_KEY"],
        )
