-- Health stage is sealed because it is personal health data.
ALTER TABLE users ADD COLUMN IF NOT EXISTS stage_sealed BYTEA;
