CREATE TABLE IF NOT EXISTS google_identities (
    subject VARCHAR(255) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    email_normalized VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_google_identities_user_id ON google_identities(user_id);
CREATE INDEX IF NOT EXISTS idx_google_identities_email_normalized ON google_identities(email_normalized);
