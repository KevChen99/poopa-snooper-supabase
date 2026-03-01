-- Migration 001: cameras table
--
-- Apply via Supabase CLI:  supabase db push
-- Or reset + apply:        supabase db reset
--
-- Note: IP address is intentionally NOT stored — it is always obtained
-- fresh from WS-Discovery at runtime and held only in the local registry.

CREATE TYPE camera_status AS ENUM ('connected', 'disconnected');

CREATE TABLE IF NOT EXISTS cameras (
    id               UUID PRIMARY KEY,           -- ONVIF Endpoint Reference UUID
    status           camera_status NOT NULL DEFAULT 'disconnected',
    reason           TEXT NOT NULL DEFAULT '',   -- last status change reason
    username         TEXT,                        -- camera login username
    encrypted_secret BYTEA,                       -- plaintext password as raw UTF-8 bytes (LOCAL_DEV)
    prompt           TEXT,                         -- JSON array of selected violation tags; NULL = not yet configured
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Automatically keep updated_at current on every row update
CREATE OR REPLACE FUNCTION _set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER cameras_updated_at
    BEFORE UPDATE ON cameras
    FOR EACH ROW EXECUTE FUNCTION _set_updated_at();
