ALTER TABLE partner_alert_preferences
    ADD COLUMN IF NOT EXISTS symptom_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS symptom_time VARCHAR(5) NOT NULL DEFAULT '09:00'
        CHECK (symptom_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');
