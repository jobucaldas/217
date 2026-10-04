-- Personal data is sealed by the API (AES-256-GCM, key outside the database)
-- before it is stored. 018 (Go) seals existing rows; 019 drops the plaintext.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS email_sealed BYTEA,
    ADD COLUMN IF NOT EXISTS name_sealed BYTEA,
    -- HMAC of the normalized email, for the legacy-account link lookup.
    ADD COLUMN IF NOT EXISTS email_index BYTEA;

ALTER TABLE entries ADD COLUMN IF NOT EXISTS sealed BYTEA;

ALTER TABLE partner_notes ADD COLUMN IF NOT EXISTS body_sealed BYTEA;

ALTER TABLE calendar_shares
    ADD COLUMN IF NOT EXISTS invite_sealed BYTEA,
    ADD COLUMN IF NOT EXISTS invite_index BYTEA;

ALTER TABLE push_subscriptions
    ADD COLUMN IF NOT EXISTS sealed BYTEA,
    ADD COLUMN IF NOT EXISTS endpoint_index BYTEA;

-- OAuth attempts live five minutes: restart any in flight with sealed secrets.
DELETE FROM oauth_attempts;
ALTER TABLE oauth_attempts
    DROP COLUMN IF EXISTS code_verifier,
    DROP COLUMN IF EXISTS nonce,
    ADD COLUMN sealed BYTEA NOT NULL;

-- Data minimization: client IP, user agent and last-seen were never read.
ALTER TABLE sessions
    DROP COLUMN IF EXISTS user_agent,
    DROP COLUMN IF EXISTS ip_address,
    DROP COLUMN IF EXISTS last_seen;

-- A plaintext email copy nothing reads, and the pre-WorkOS Google sign-in table.
DROP INDEX IF EXISTS idx_workos_identities_email_normalized;
ALTER TABLE workos_identities DROP COLUMN IF EXISTS email_normalized;
DROP TABLE IF EXISTS google_identities;
