-- Display name and birth month, sealed together because they are personal data.
ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_sealed BYTEA;
