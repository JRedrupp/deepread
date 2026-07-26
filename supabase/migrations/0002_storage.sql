-- Storage bucket for rendered article packages (index.html + images, zipped).
-- Objects are named "<article_id>.zip" (see deepread_worker.renderer).

insert into storage.buckets (id, name, public)
values ('articles', 'articles', false)
on conflict (id) do nothing;

-- A user may download an article's zip only if they're subscribed to the
-- feed it belongs to — mirrors the `articles` select policy in 0001_init.sql.
create policy "users download articles for their subscribed feeds"
    on storage.objects for select
    to authenticated
    using (
        bucket_id = 'articles'
        and exists (
            select 1
            from articles a
            join user_feed_subscriptions ufs on ufs.feed_id = a.feed_id
            where a.storage_path = storage.objects.name
              and ufs.user_id = auth.uid()
        )
    );
