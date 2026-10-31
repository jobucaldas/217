-- Messages go both ways: sender names who wrote the row (the body stays
-- sealed in body_sealed, its seal bound to the sender). Existing rows were
-- all written by partners.
ALTER TABLE partner_notes
    ADD COLUMN IF NOT EXISTS sender TEXT NOT NULL DEFAULT 'partner';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'partner_notes_sender_check'
    ) THEN
        ALTER TABLE partner_notes
            ADD CONSTRAINT partner_notes_sender_check CHECK (sender IN ('owner', 'partner'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_partner_notes_partner_created
    ON partner_notes (partner_id, created_at DESC);
