-- Migration: invites table
-- Invite-only registration with 24-hour secure tokens.

CREATE TYPE invite_status AS ENUM ('pending', 'accepted', 'expired', 'revoked');

CREATE TABLE invites (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id      UUID NOT NULL REFERENCES organizations(id),
    email       TEXT NOT NULL,
    role_id     UUID NOT NULL REFERENCES roles(id),
    token       TEXT NOT NULL UNIQUE,
    status      invite_status NOT NULL DEFAULT 'pending',
    invited_by  UUID NOT NULL REFERENCES users(id),
    expires_at  TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_invites_token ON invites(token) WHERE status = 'pending';
CREATE INDEX idx_invites_email_org ON invites(email, org_id);
