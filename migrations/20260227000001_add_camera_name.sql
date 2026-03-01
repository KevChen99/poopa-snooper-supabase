-- Migration 003: add name column to cameras table

ALTER TABLE cameras ADD COLUMN IF NOT EXISTS name TEXT NOT NULL DEFAULT '';
