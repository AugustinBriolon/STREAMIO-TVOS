-- Device sessions (ADR 0022): every token issued since this migration names a session,
-- so one device can be signed out without touching the others.
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    device_name TEXT NOT NULL,
    device_model TEXT,
    created_at_ms INTEGER NOT NULL,
    last_seen_at_ms INTEGER NOT NULL,
    revoked_at_ms INTEGER,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS sessions_by_account ON sessions (account_id, revoked_at_ms);
