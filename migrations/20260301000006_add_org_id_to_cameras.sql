-- Migration: add org_id FK to cameras table
-- Added as nullable first; the seed migration (009) backfills and sets NOT NULL.

ALTER TABLE cameras ADD COLUMN IF NOT EXISTS org_id UUID REFERENCES organizations(id);
CREATE INDEX idx_cameras_org ON cameras(org_id);
