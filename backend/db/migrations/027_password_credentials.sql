-- First-party email+password sign-in. One credential row per user; the hash
-- is Argon2id (internal/passwordauth). The legacy users.password_hash column
-- stays untouched until the cleanup milestone.
CREATE TABLE IF NOT EXISTS password_credentials (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Address verification codes (only used when SMTP is configured). One
-- pending code per user; only its hash is stored.
CREATE TABLE IF NOT EXISTS email_verifications (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    code_hash VARCHAR(64) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);
