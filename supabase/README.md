# Supabase schema

Migrations in `migrations/` are plain SQL, applied in order (`0001_init.sql`, then `0002_storage.sql`).

**Easiest path (no CLI needed):** open your project's SQL Editor in the Supabase dashboard, paste the contents of `0001_init.sql`, run it, then do the same for `0002_storage.sql`. It runs as the `postgres` role, so `0002`'s `storage.objects` policy is permitted.

If you have the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) installed, you can instead do:

```
supabase link --project-ref <your-project-ref>
supabase db push
```

Supabase's hosted Postgres already grants the `authenticated`/`anon` roles table-level `SELECT`/`INSERT`/etc. privileges by default and enables RLS on `storage.objects` out of the box — the policies here are what actually restrict access on top of that. If you ever test these migrations against a plain (non-Supabase) Postgres instance, you'll need to replicate both of those yourself, or the policies will appear to have no effect.

The worker service (`backend/`) connects with the **service role key**, which bypasses RLS entirely — that's intentional, since it's the only thing that writes to the shared `feeds`/`articles` tables.
