# Supabase schema

Migrations in `migrations/` are plain SQL, named `NNNN_description.sql` and applied in numeric
order (`0001_init.sql`, `0002_storage.sql`, ...). This `NNNN` prefix is compatible with the
Supabase CLI's migration filename parser (any run of leading digits, not specifically a
timestamp) — when adding a new migration, keep using the next `NNNN`, there's no need to switch to
`supabase migration new`'s timestamp-based naming.

**Primary path — automatic:** `.github/workflows/release.yml` runs `supabase db push` against
production on every merge to `main` (i.e. every `release/*`/`hotfix/*` merge). Just add a new
`NNNN_description.sql` file in a normal PR into `develop`; it gets applied automatically the next
time that change reaches `main`. This requires the `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`,
and `SUPABASE_PROJECT_ID` repo secrets to be set, and the project to already be linked with a fully
reconciled migration history (see below) — a fresh Supabase project just needs those three secrets
set and no further one-time setup.

**Manual fallback (no CLI needed):** open your project's SQL Editor in the Supabase dashboard,
paste the contents of each migration file in order, and run it. It runs as the `postgres` role, so
`0002`'s `storage.objects` policy is permitted.

If you have the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) installed, you can instead do the same locally:

```
supabase link --project-ref <your-project-ref>
supabase db push
```

**One-time setup note:** this project's first three migrations (`0001`-`0003`) were originally
applied by hand via the SQL Editor, before CI-driven migrations existed. If you're pointing this
CI workflow at that same production project, its CLI migration-history table needs to be told
those three are already applied — otherwise the first `db push` will try to replay
`create table articles` (etc.) against a database that already has it, and fail:

```
supabase link --project-ref <your-project-ref>
supabase migration repair --status applied 0001 0002 0003
supabase migration list   # confirm all three show applied remotely, zero pending, before relying on CI
```

This is a one-time step per production project, not something CI does automatically — if you ever
point this repo at a brand-new, empty Supabase project instead, skip it and just run `db push`
directly.

Also check `config.toml`'s `[db] major_version` (currently `17`, `supabase init`'s default) against
the real project before relying on CI: run `SHOW server_version;` in the SQL Editor and correct it
if it doesn't match. This doesn't affect `db push` of plain SQL migrations, but does affect any
local `supabase start`/`db diff` usage against a mismatched Postgres major version.

Supabase's hosted Postgres already grants the `authenticated`/`anon` roles table-level `SELECT`/`INSERT`/etc. privileges by default and enables RLS on `storage.objects` out of the box — the policies here are what actually restrict access on top of that. If you ever test these migrations against a plain (non-Supabase) Postgres instance, you'll need to replicate both of those yourself, or the policies will appear to have no effect.

The worker service (`backend/`) connects with the **service role key**, which bypasses RLS entirely — that's intentional, since it's the only thing that writes to the shared `feeds`/`articles` tables.
