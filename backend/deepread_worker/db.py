from typing import Any, cast

from supabase import Client, create_client

from .config import Settings


def make_client(settings: Settings) -> Client:
    """Service-role client: the worker writes to the shared `feeds` and
    `articles` tables directly, bypassing RLS (which exists to scope
    per-user subscription data on the client side, not to gate the worker).
    """
    return create_client(settings.supabase_url, settings.supabase_service_role_key)


def rows(data: object) -> list[dict[str, Any]]:
    """postgrest-py types `.execute().data` as a broad recursive JSON union,
    but every query in this worker actually selects a list of row dicts.
    Narrows that at the one boundary instead of scattering casts/type:ignore
    comments across every call site that indexes into a query result."""
    return cast(list[dict[str, Any]], data)
