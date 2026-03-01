-- Migration: add ip_address column to cameras table

ALTER TABLE cameras ADD COLUMN IF NOT EXISTS ip_address TEXT NOT NULL DEFAULT '';
