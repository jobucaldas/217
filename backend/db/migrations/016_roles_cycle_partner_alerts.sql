-- Role is chosen explicitly after first sign-in: NULL = not chosen yet.
ALTER TABLE users ALTER COLUMN role DROP DEFAULT;
ALTER TABLE users ALTER COLUMN role DROP NOT NULL;

-- Accounts that defaulted to owner but never logged a day or shared anything
-- get to pick their role on next sign-in.
UPDATE users u SET role = NULL, updated_at = NOW()
WHERE u.role = 'owner'
  AND NOT EXISTS (SELECT 1 FROM entries e WHERE e.user_id = u.id)
  AND NOT EXISTS (SELECT 1 FROM calendar_shares s WHERE s.owner_id = u.id);

-- Period days logged by the calendar owner (drives cycle/PMS predictions).
ALTER TABLE entries
    ADD COLUMN IF NOT EXISTS period BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_entries_user_period
    ON entries (user_id, date) WHERE period;

-- Partner notification choices (PMS heads-up, pill not logged), each with its own time.
CREATE TABLE IF NOT EXISTS partner_alert_preferences (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    pms_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    pms_time VARCHAR(5) NOT NULL DEFAULT '09:00'
        CHECK (pms_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
    pill_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    pill_time VARCHAR(5) NOT NULL DEFAULT '21:00'
        CHECK (pill_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
