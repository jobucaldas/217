-- Allow note/heart-only entries with no Taken/Missed status (Em aberto).
ALTER TABLE entries ALTER COLUMN taken DROP NOT NULL;
