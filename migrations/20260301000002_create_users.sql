-- Migration: users table
-- Links to Supabase auth.users via auth_id.
-- Soft-deleted via deleted_at. Partial unique index allows re-invite of deleted emails.

CREATE TABLE users (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_id           UUID NOT NULL UNIQUE,
    org_id            UUID NOT NULL REFERENCES organizations(id),
    role_id           UUID NOT NULL REFERENCES roles(id),
    email             TEXT NOT NULL,
    display_name      TEXT NOT NULL DEFAULT '',
    is_platform_admin BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at        TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_users_org_email_active
    ON users(org_id, email) WHERE deleted_at IS NULL;

CREATE INDEX idx_users_auth_id ON users(auth_id) WHERE deleted_at IS NULL;

CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION _set_updated_at();
