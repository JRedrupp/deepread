from supabase import Client, create_client

from .config import Settings


def make_client(settings: Settings) -> Client:
    """Service-role client: the worker writes to the shared `feeds` and
    `articles` tables directly, bypassing RLS (which exists to scope
    per-user subscription data on the client side, not to gate the worker).
    """
    return create_client(settings.supabase_url, settings.supabase_service_role_key)
