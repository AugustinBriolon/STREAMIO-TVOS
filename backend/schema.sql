-- Comptes du foyer
CREATE TABLE IF NOT EXISTS accounts (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    nickname TEXT,
    password_hash TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Codes d'appairage temporaires pour Apple TV
CREATE TABLE IF NOT EXISTS pairing_codes (
    code TEXT PRIMARY KEY,
    account_id TEXT,
    status TEXT DEFAULT 'pending', -- 'pending', 'authorized', 'expired'
    device_name TEXT,
    expires_at DATETIME NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Profils du foyer
CREATE TABLE IF NOT EXISTS profiles (
    id TEXT NOT NULL,
    account_id TEXT NOT NULL,
    name TEXT NOT NULL,
    avatar_json TEXT NOT NULL,
    sort_order INTEGER DEFAULT 0,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (account_id, id),
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Progression de lecture (Reprendre la lecture)
CREATE TABLE IF NOT EXISTS playback_progress (
    account_id TEXT NOT NULL,
    profile_id TEXT NOT NULL,
    video_id TEXT NOT NULL,
    item_json TEXT NOT NULL,
    position REAL NOT NULL,
    duration REAL NOT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at_ms INTEGER,
    PRIMARY KEY (account_id, profile_id, video_id),
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- "Ma liste" par profil
CREATE TABLE IF NOT EXISTS my_list (
    account_id TEXT NOT NULL,
    profile_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    item_json TEXT NOT NULL,
    added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at_ms INTEGER,
    PRIMARY KEY (account_id, profile_id, item_id),
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Tombstones pour propager les suppressions multi-écrans sans réapparition
CREATE TABLE IF NOT EXISTS sync_tombstones (
    account_id TEXT NOT NULL,
    profile_id TEXT NOT NULL,
    entity_type TEXT NOT NULL, -- 'my_list' | 'progress'
    entity_id TEXT NOT NULL,
    deleted_at_ms INTEGER NOT NULL,
    PRIMARY KEY (account_id, profile_id, entity_type, entity_id),
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Addons / extensions configurés
CREATE TABLE IF NOT EXISTS addons (
    account_id TEXT NOT NULL,
    manifest_url TEXT NOT NULL,
    installed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (account_id, manifest_url),
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);
