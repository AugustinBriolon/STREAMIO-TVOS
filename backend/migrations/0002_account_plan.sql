-- Free / Pro / Ultra (spec 2026-11-12-loge-tiers-design): plan on the account,
-- session kind pools (tv vs browser), optional display_name for rename.
ALTER TABLE accounts ADD COLUMN plan TEXT NOT NULL DEFAULT 'free';
ALTER TABLE accounts ADD COLUMN plan_expires_at_ms INTEGER;
ALTER TABLE accounts ADD COLUMN plan_product_id TEXT;

ALTER TABLE sessions ADD COLUMN device_kind TEXT NOT NULL DEFAULT 'tv';
ALTER TABLE sessions ADD COLUMN display_name TEXT;

CREATE INDEX IF NOT EXISTS sessions_by_account_kind
  ON sessions (account_id, device_kind, revoked_at_ms);
