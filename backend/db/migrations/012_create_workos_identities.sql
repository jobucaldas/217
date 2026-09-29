CREATE TABLE IF NOT EXISTS workos_identities (
    subject VARCHAR(255) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    email_normalized VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_workos_identities_user_id ON workos_identities(user_id);
CREATE INDEX IF NOT EXISTS idx_workos_identities_email_normalized ON workos_identities(email_normalized);

-- Best-effort carry-forward of legacy Google subjects is intentionally skipped:
-- WorkOS user IDs differ, so accounts reconnect via verified-email linking on next AuthKit sign-in.
