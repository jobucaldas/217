-- Repeat the owner's "pill not logged" reminder every N minutes until logged or day end.
ALTER TABLE reminder_preferences
    ADD COLUMN IF NOT EXISTS repeat_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS repeat_minutes INT NOT NULL DEFAULT 15
        CHECK (repeat_minutes BETWEEN 1 AND 120);
