-- Set at render-claim time (deepread_worker.renderer._render_one) so the
-- cleanup sweep (deepread_worker.cleanup) can detect a claim that's gone
-- stale (crashed worker, or a transient failure that never got recorded)
-- and reclaim the row back to pending/failed instead of leaving it stuck
-- in 'rendering' forever.
alter table articles add column claimed_at timestamptz;
