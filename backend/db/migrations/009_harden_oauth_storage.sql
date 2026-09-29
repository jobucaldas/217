CREATE INDEX IF NOT EXISTS idx_users_email_normalized ON users (LOWER(email));

UPDATE sessions SET expires_at = created_at + INTERVAL '1 second' WHERE expires_at IS NULL;
ALTER TABLE sessions ALTER COLUMN expires_at SET NOT NULL;
ALTER TABLE sessions ADD CONSTRAINT sessions_expiry_after_creation CHECK (expires_at > created_at) NOT VALID;
ALTER TABLE sessions VALIDATE CONSTRAINT sessions_expiry_after_creation;
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at);

ALTER TABLE oauth_attempts ADD CONSTRAINT oauth_attempts_expiry_after_creation CHECK (expires_at > created_at) NOT VALID;
ALTER TABLE oauth_attempts VALIDATE CONSTRAINT oauth_attempts_expiry_after_creation;
