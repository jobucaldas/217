-- Roles: owner (girl / calendar owner) or partner (boyfriend).
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'owner';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'users_role_check'
    ) THEN
        ALTER TABLE users
            ADD CONSTRAINT users_role_check CHECK (role IN ('owner', 'partner'));
    END IF;
END $$;

-- Invite / share between calendar owner and one partner.
CREATE TABLE IF NOT EXISTS calendar_shares (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    partner_id UUID REFERENCES users(id) ON DELETE SET NULL,
    invite_code TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('open', 'active', 'revoked')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT calendar_shares_invite_code_unique UNIQUE (invite_code)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_calendar_shares_owner_live
    ON calendar_shares (owner_id)
    WHERE status IN ('open', 'active');

CREATE UNIQUE INDEX IF NOT EXISTS idx_calendar_shares_partner_live
    ON calendar_shares (partner_id)
    WHERE partner_id IS NOT NULL AND status IN ('open', 'active');

CREATE INDEX IF NOT EXISTS idx_calendar_shares_invite_code
    ON calendar_shares (invite_code);

-- General (not day-tied) notes from partner → owner inbox.
CREATE TABLE IF NOT EXISTS partner_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    partner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    read_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_partner_notes_owner_created
    ON partner_notes (owner_id, created_at DESC);
