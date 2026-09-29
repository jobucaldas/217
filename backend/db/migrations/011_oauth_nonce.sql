-- In-flight attempts predate nonce binding and must restart authorization.
DELETE FROM oauth_attempts;
ALTER TABLE oauth_attempts ADD COLUMN nonce TEXT NOT NULL CHECK (nonce <> '');
