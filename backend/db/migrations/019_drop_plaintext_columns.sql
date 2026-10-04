-- 018 sealed every row; the plaintext columns (and their indexes) go.

ALTER TABLE users
    DROP COLUMN IF EXISTS email,
    DROP COLUMN IF EXISTS name,
    ALTER COLUMN email_sealed SET NOT NULL,
    ALTER COLUMN name_sealed SET NOT NULL,
    ALTER COLUMN email_index SET NOT NULL;
DROP INDEX IF EXISTS idx_users_email;
DROP INDEX IF EXISTS idx_users_email_normalized;
CREATE INDEX IF NOT EXISTS idx_users_email_index ON users (email_index);

DROP INDEX IF EXISTS idx_entries_user_period;
ALTER TABLE entries
    DROP COLUMN IF EXISTS taken,
    DROP COLUMN IF EXISTS notes,
    DROP COLUMN IF EXISTS heart,
    DROP COLUMN IF EXISTS period,
    ALTER COLUMN sealed SET NOT NULL;

ALTER TABLE partner_notes
    DROP COLUMN IF EXISTS body,
    ALTER COLUMN body_sealed SET NOT NULL;

DROP INDEX IF EXISTS idx_calendar_shares_invite_code;
ALTER TABLE calendar_shares
    DROP COLUMN IF EXISTS invite_code,
    ALTER COLUMN invite_sealed SET NOT NULL,
    ALTER COLUMN invite_index SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_calendar_shares_invite_index ON calendar_shares (invite_index);

ALTER TABLE push_subscriptions
    DROP COLUMN IF EXISTS endpoint,
    DROP COLUMN IF EXISTS p256dh,
    DROP COLUMN IF EXISTS auth,
    ALTER COLUMN sealed SET NOT NULL,
    ALTER COLUMN endpoint_index SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_push_subscriptions_endpoint_index ON push_subscriptions (endpoint_index);
