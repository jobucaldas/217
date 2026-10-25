-- Minutes between repeated pill-not-logged alerts; 0 = off (the default, so
-- rows saved before this migration stay off). The API keeps 1..120 when on.
ALTER TABLE partner_alert_preferences
    ADD COLUMN IF NOT EXISTS pill_repeat_minutes INTEGER NOT NULL DEFAULT 0
        CHECK (pill_repeat_minutes BETWEEN 0 AND 120);
