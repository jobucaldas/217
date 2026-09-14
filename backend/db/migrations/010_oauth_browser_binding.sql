-- OAuth attempts are ephemeral. Existing rows cannot be safely browser-bound.
DELETE FROM oauth_attempts;

ALTER TABLE oauth_attempts ADD COLUMN IF NOT EXISTS binding_hash VARCHAR(64);
ALTER TABLE oauth_attempts ALTER COLUMN binding_hash SET NOT NULL;

-- 009 briefly shipped a uniqueness constraint that legacy case-duplicates may
-- violate. Keep normalized lookups fast without preventing migration startup.
DROP INDEX IF EXISTS idx_users_email_normalized_unique;
CREATE INDEX IF NOT EXISTS idx_users_email_normalized ON users (LOWER(email));

CREATE INDEX IF NOT EXISTS idx_oauth_attempts_cleanup
    ON oauth_attempts (expires_at, consumed_at);
