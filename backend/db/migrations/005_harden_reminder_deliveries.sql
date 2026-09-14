ALTER TABLE reminder_deliveries
    ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS attempts INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE reminder_deliveries DROP CONSTRAINT IF EXISTS reminder_deliveries_status_check;
ALTER TABLE reminder_deliveries ADD CONSTRAINT reminder_deliveries_status_check
    CHECK (status IN ('sending', 'retry', 'sent'));

CREATE INDEX IF NOT EXISTS idx_reminder_deliveries_retry
    ON reminder_deliveries (next_attempt_at)
    WHERE status <> 'sent';
