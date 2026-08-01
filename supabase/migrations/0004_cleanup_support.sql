-- Supports the retention TTL queries in deepread_worker.cleanup:
--   status = 'ready' AND (published_at < cutoff
--                         OR (published_at IS NULL AND created_at < cutoff))
-- Two composite indexes let the planner satisfy either branch of that OR.
create index articles_status_published_at_idx on articles (status, published_at);
create index articles_status_created_at_idx on articles (status, created_at);
