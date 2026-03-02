-- Migration: add org_id FK to violations table
-- Added as nullable first; the seed migration (009) backfills and sets NOT NULL.

ALTER TABLE violations ADD COLUMN org_id UUID REFERENCES organizations(id);
CREATE INDEX idx_violations_org ON violations(org_id);
