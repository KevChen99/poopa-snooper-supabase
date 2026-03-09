-- Migration: audit_logs table
-- Append-only, immutable audit trail.
-- details JSONB is SELF-CONTAINED: always includes actor_email, actor_display_name,
-- actor_role_name so logs are readable without JOINs even after user/role soft-deletion.

CREATE TABLE audit_logs (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id        UUID NOT NULL REFERENCES organizations(id),
    actor_id      UUID REFERENCES users(id),
    action        TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    resource_id   UUID,
    details       JSONB NOT NULL DEFAULT '{}'::JSONB,
    ip_address    INET,
    user_agent    TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- IMMUTABILITY ENFORCEMENT: prevent all UPDATE and DELETE operations
CREATE OR REPLACE FUNCTION _prevent_audit_log_mutation()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'audit_logs are immutable: UPDATE and DELETE are prohibited';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_logs_immutable
    BEFORE UPDATE OR DELETE ON audit_logs
    FOR EACH ROW EXECUTE FUNCTION _prevent_audit_log_mutation();

CREATE INDEX idx_audit_org_created ON audit_logs(org_id, created_at DESC);
CREATE INDEX idx_audit_actor ON audit_logs(actor_id, created_at DESC);
CREATE INDEX idx_audit_resource ON audit_logs(resource_type, resource_id, created_at DESC);
CREATE INDEX idx_audit_action ON audit_logs(action, created_at DESC);
