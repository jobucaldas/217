-- Hardware-bound device keys (Android Keystore). The app signs a one-time
-- challenge with the private key, which never leaves the device, to renew
-- its session without signing in again.
CREATE TABLE IF NOT EXISTS device_keys (
    id VARCHAR(64) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    public_key BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    challenge_hash VARCHAR(64),
    challenge_expires_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_device_keys_user_id ON device_keys(user_id);

-- Revoking a device key ends the sessions it opened.
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS device_key_id VARCHAR(64)
    REFERENCES device_keys(id) ON DELETE CASCADE;
