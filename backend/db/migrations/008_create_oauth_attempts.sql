CREATE TABLE IF NOT EXISTS oauth_attempts (
    state_hash VARCHAR(64) PRIMARY KEY,
    code_verifier TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_oauth_attempts_expires_at ON oauth_attempts(expires_at);
