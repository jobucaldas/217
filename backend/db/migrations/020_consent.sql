-- LGPD art. 11: specific, recorded consent before processing health data.
-- consent_version is the privacy notice version the user agreed to (0 = none).
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS consent_version INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS consented_at TIMESTAMPTZ;
