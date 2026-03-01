-- Migration 002: violations table
--
-- Apply via Supabase CLI:  supabase db push
-- Or reset + apply:        supabase db reset

CREATE TYPE violation_status AS ENUM ('needs_review', 'confirmed', 'rejected');

CREATE TABLE IF NOT EXISTS violations (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    camera_uuid   UUID NOT NULL REFERENCES cameras(id),
    violation_tag TEXT NOT NULL,                           -- e.g. "Dog Biohazard"
    violation     BOOLEAN NOT NULL,                        -- Gemini's verdict: was a violation present?
    confidence    INTEGER NOT NULL CHECK (confidence >= 0 AND confidence <= 100),
    summary       TEXT NOT NULL,                           -- Gemini's description of the clip
    clip_path     TEXT NOT NULL,                           -- Supabase storage path: <camera_uuid>/<timestamp>.mp4
    timestamp     TIMESTAMPTZ NOT NULL DEFAULT now(),      -- when the violation event occurred
    status        violation_status NOT NULL DEFAULT 'needs_review',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reuse the existing _set_updated_at() trigger function (defined in 001)
CREATE TRIGGER violations_updated_at
    BEFORE UPDATE ON violations
    FOR EACH ROW EXECUTE FUNCTION _set_updated_at();
