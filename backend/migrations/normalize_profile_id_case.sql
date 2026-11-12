-- Canonicalize profile UUIDs to lowercase (web + Worker contract).
-- D1 UNIQUE(account_id, id) is case-sensitive; tvOS uuidString is uppercase.

INSERT INTO profiles (account_id, id, name, avatar_json, sort_order, updated_at)
SELECT account_id, lower(id), name, avatar_json, sort_order, updated_at
FROM profiles AS src
WHERE src.id != lower(src.id)
  AND NOT EXISTS (
    SELECT 1 FROM profiles AS dst
    WHERE dst.account_id = src.account_id AND dst.id = lower(src.id)
  );

INSERT INTO playback_progress (account_id, profile_id, video_id, item_json, position, duration, updated_at, updated_at_ms)
SELECT account_id, lower(profile_id), video_id, item_json, position, duration, updated_at, updated_at_ms
FROM playback_progress AS src
WHERE src.profile_id != lower(src.profile_id)
  AND NOT EXISTS (
    SELECT 1 FROM playback_progress AS dst
    WHERE dst.account_id = src.account_id
      AND dst.profile_id = lower(src.profile_id)
      AND dst.video_id = src.video_id
  );

DELETE FROM playback_progress WHERE profile_id != lower(profile_id);

INSERT INTO my_list (account_id, profile_id, item_id, item_json, added_at, updated_at_ms)
SELECT account_id, lower(profile_id), item_id, item_json, added_at, updated_at_ms
FROM my_list AS src
WHERE src.profile_id != lower(src.profile_id)
  AND NOT EXISTS (
    SELECT 1 FROM my_list AS dst
    WHERE dst.account_id = src.account_id
      AND dst.profile_id = lower(src.profile_id)
      AND dst.item_id = src.item_id
  );

DELETE FROM my_list WHERE profile_id != lower(profile_id);

INSERT INTO sync_tombstones (account_id, profile_id, entity_type, entity_id, deleted_at_ms)
SELECT
  account_id,
  lower(profile_id),
  entity_type,
  CASE WHEN entity_type = 'profile' THEN lower(entity_id) ELSE entity_id END,
  deleted_at_ms
FROM sync_tombstones AS src
WHERE (
    src.profile_id != lower(src.profile_id)
    OR (src.entity_type = 'profile' AND src.entity_id != lower(src.entity_id))
  )
  AND NOT EXISTS (
    SELECT 1 FROM sync_tombstones AS dst
    WHERE dst.account_id = src.account_id
      AND dst.profile_id = lower(src.profile_id)
      AND dst.entity_type = src.entity_type
      AND dst.entity_id = CASE WHEN src.entity_type = 'profile' THEN lower(src.entity_id) ELSE src.entity_id END
  );

DELETE FROM sync_tombstones
WHERE profile_id != lower(profile_id)
   OR (entity_type = 'profile' AND entity_id != lower(entity_id));

DELETE FROM profiles WHERE id != lower(id);
