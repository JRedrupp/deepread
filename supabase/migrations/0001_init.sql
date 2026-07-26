-- Initial schema: shared feed/article cache + per-user subscriptions.
--
-- Design note: `feeds` and `articles` are global tables shared across all
-- users (this is what makes the shared-rendering-cache model work — one
-- render serves every subscriber of that feed). Only `user_feed_subscriptions`
-- is genuinely per-user private data.
--
-- The worker service connects with the service_role key, which bypasses RLS
-- entirely — the policies below govern what the Flutter client (using the
-- publishable/anon key + a user's session) is allowed to do directly.

create extension if not exists "pgcrypto";

create table feeds (
    id uuid primary key default gen_random_uuid(),
    url text not null unique,
    title text,
    last_polled_at timestamptz,
    poll_interval_seconds integer not null default 900,
    created_at timestamptz not null default now()
);

create table user_feed_subscriptions (
    user_id uuid not null references auth.users (id) on delete cascade,
    feed_id uuid not null references feeds (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_id, feed_id)
);

create table articles (
    id uuid primary key default gen_random_uuid(),
    feed_id uuid not null references feeds (id) on delete cascade,
    canonical_url text not null unique,
    status text not null default 'pending'
        check (status in ('pending', 'rendering', 'ready', 'failed')),
    failure_reason text,
    retry_count integer not null default 0,
    title text,
    byline text,
    -- RSS-provided summary, captured at poll time. Used as the only
    -- offline-readable content for paywalled articles (storage_path stays
    -- null in that case) — see deepread_worker.renderer's paywall branch.
    summary text,
    published_at timestamptz,
    rendered_at timestamptz,
    storage_path text,
    is_paywalled boolean not null default false,
    created_at timestamptz not null default now()
);

create index articles_feed_id_idx on articles (feed_id);
create index articles_status_idx on articles (status);

create table takedown_requests (
    id uuid primary key default gen_random_uuid(),
    article_id uuid references articles (id) on delete set null,
    reported_url text,
    requester_contact text not null,
    reason text not null,
    status text not null default 'open'
        check (status in ('open', 'reviewing', 'resolved', 'rejected')),
    created_at timestamptz not null default now()
);

alter table feeds enable row level security;
alter table user_feed_subscriptions enable row level security;
alter table articles enable row level security;
alter table takedown_requests enable row level security;

-- feeds: any authenticated user can look up / add a feed by URL.
-- Updates (last_polled_at, title refresh) are worker-only (service_role
-- bypasses RLS, so no update policy is needed/granted here).
create policy "feeds are readable by any authenticated user"
    on feeds for select
    to authenticated
    using (true);

create policy "authenticated users can register a new feed"
    on feeds for insert
    to authenticated
    with check (true);

-- user_feed_subscriptions: strictly private to the owning user.
create policy "users manage their own subscriptions"
    on user_feed_subscriptions for all
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- articles: a user can only see articles belonging to feeds they're
-- subscribed to (even though the underlying render is shared/global).
-- Writes are worker-only.
create policy "users read articles for their subscribed feeds"
    on articles for select
    to authenticated
    using (
        exists (
            select 1
            from user_feed_subscriptions ufs
            where ufs.feed_id = articles.feed_id
              and ufs.user_id = auth.uid()
        )
    );

-- takedown_requests: anyone can file one; only the worker/admin (service_role)
-- can read or update them.
create policy "authenticated users can file a takedown request"
    on takedown_requests for insert
    to authenticated
    with check (true);
