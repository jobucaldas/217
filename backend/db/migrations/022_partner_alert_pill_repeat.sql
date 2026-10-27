-- Repeat the pill-not-logged alert every N minutes until logged or day end.
ALTER TABLE partner_alert_preferences
    ADD COLUMN IF NOT EXISTS pill_repeat_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS pill_repeat_minutes INT NOT NULL DEFAULT 15
        CHECK (pill_repeat_minutes BETWEEN 1 AND 120);
