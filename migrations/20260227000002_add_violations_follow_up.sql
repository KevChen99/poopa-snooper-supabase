-- Migration 004: add follow_up_status column to violations table

ALTER TABLE violations ADD COLUMN IF NOT EXISTS follow_up_status TEXT;
