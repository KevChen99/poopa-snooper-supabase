-- Migration: soft-delete support for cameras
-- Adds deleted_at column; NULL means not deleted.

ALTER TABLE cameras ADD COLUMN deleted_at TIMESTAMPTZ;

CREATE INDEX idx_cameras_deleted_at ON cameras(deleted_at) WHERE deleted_at IS NULL;
