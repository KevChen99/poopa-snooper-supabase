-- Migration: RLS policies, JWT helper functions, and custom access token hook.
-- This migration MUST be applied simultaneously with the new backend/frontend code.

-- ── JWT Helper Functions ─────────────────────────────────────────────────────
-- Defined in public schema (migrations cannot write to the auth schema).

CREATE OR REPLACE FUNCTION public.user_org_id()
RETURNS UUID AS $$
    SELECT COALESCE(
        (current_setting('request.jwt.claims', true)::JSONB ->> 'org_id')::UUID,
        '00000000-0000-0000-0000-000000000000'::UUID
    );
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS BOOLEAN AS $$
    SELECT COALESCE(
        (current_setting('request.jwt.claims', true)::JSONB ->> 'is_platform_admin')::BOOLEAN,
        FALSE
    );
$$ LANGUAGE SQL STABLE;

-- ── Custom Access Token Hook ─────────────────────────────────────────────────
-- Called by Supabase Auth on every token refresh.
-- Injects user_id, org_id, role_id, is_platform_admin, and flattened permissions[] into the JWT.

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event JSONB)
RETURNS JSONB AS $$
DECLARE
    _auth_id UUID;
    _user RECORD;
    _permissions TEXT[];
    _claims JSONB;
BEGIN
    _auth_id := (event ->> 'user_id')::UUID;

    -- Look up the application user (must be active, in an active org)
    SELECT u.id, u.org_id, u.role_id, u.is_platform_admin, u.email,
           u.display_name, r.hierarchy_level, r.name AS role_name
    INTO _user
    FROM users u
    JOIN roles r ON r.id = u.role_id
    JOIN organizations o ON o.id = u.org_id
    WHERE u.auth_id = _auth_id
      AND u.deleted_at IS NULL
      AND o.deleted_at IS NULL
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN event;
    END IF;

    -- Flatten permissions: collect all permissions from roles at or below
    -- the user's hierarchy_level within the same org
    SELECT ARRAY_AGG(DISTINCT p.key)
    INTO _permissions
    FROM roles r
    JOIN role_permissions rp ON rp.role_id = r.id
    JOIN permissions p ON p.id = rp.permission_id
    WHERE r.org_id = _user.org_id
      AND r.hierarchy_level <= _user.hierarchy_level
      AND r.deleted_at IS NULL;

    _claims := COALESCE(event -> 'claims', '{}'::JSONB);
    _claims := jsonb_set(_claims, '{user_id}',           to_jsonb(_user.id));
    _claims := jsonb_set(_claims, '{org_id}',            to_jsonb(_user.org_id));
    _claims := jsonb_set(_claims, '{role_id}',           to_jsonb(_user.role_id));
    _claims := jsonb_set(_claims, '{is_platform_admin}', to_jsonb(_user.is_platform_admin));
    _claims := jsonb_set(_claims, '{permissions}',       to_jsonb(COALESCE(_permissions, ARRAY[]::TEXT[])));
    _claims := jsonb_set(_claims, '{email}',             to_jsonb(_user.email));
    _claims := jsonb_set(_claims, '{display_name}',      to_jsonb(_user.display_name));
    _claims := jsonb_set(_claims, '{role_name}',         to_jsonb(_user.role_name));

    event := jsonb_set(event, '{claims}', _claims);
    RETURN event;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Restrict execution of the SECURITY DEFINER hook to the auth admin role
REVOKE ALL PRIVILEGES ON FUNCTION public.custom_access_token_hook(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(JSONB) TO supabase_auth_admin;

-- The hook also needs to read from our tables
GRANT SELECT ON TABLE public.users TO supabase_auth_admin;
GRANT SELECT ON TABLE public.roles TO supabase_auth_admin;
GRANT SELECT ON TABLE public.organizations TO supabase_auth_admin;
GRANT SELECT ON TABLE public.permissions TO supabase_auth_admin;
GRANT SELECT ON TABLE public.role_permissions TO supabase_auth_admin;

-- ── Enable RLS ───────────────────────────────────────────────────────────────

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE cameras ENABLE ROW LEVEL SECURITY;
ALTER TABLE violations ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- ── RLS Policies ─────────────────────────────────────────────────────────────

-- Organizations: users see their own org, platform admins see all
CREATE POLICY org_isolation ON organizations
    FOR ALL USING (
        public.is_platform_admin() OR id = public.user_org_id()
    );

-- Cameras: org-scoped
CREATE POLICY cameras_org_isolation ON cameras
    FOR ALL USING (
        public.is_platform_admin() OR org_id = public.user_org_id()
    );

-- Violations: org-scoped
CREATE POLICY violations_org_isolation ON violations
    FOR ALL USING (
        public.is_platform_admin() OR org_id = public.user_org_id()
    );

-- Users: org-scoped
CREATE POLICY users_org_isolation ON users
    FOR ALL USING (
        public.is_platform_admin() OR org_id = public.user_org_id()
    );

-- Roles: org-scoped
CREATE POLICY roles_org_isolation ON roles
    FOR ALL USING (
        public.is_platform_admin() OR org_id = public.user_org_id()
    );

-- Role Permissions: join through roles for org scoping
CREATE POLICY rp_org_isolation ON role_permissions
    FOR ALL USING (
        public.is_platform_admin()
        OR role_id IN (SELECT id FROM roles WHERE org_id = public.user_org_id())
    );

-- Invites: org-scoped
CREATE POLICY invites_org_isolation ON invites
    FOR ALL USING (
        public.is_platform_admin() OR org_id = public.user_org_id()
    );

-- User Sessions: org-scoped via user
CREATE POLICY sessions_org_isolation ON user_sessions
    FOR ALL USING (
        public.is_platform_admin()
        OR user_id IN (SELECT id FROM users WHERE org_id = public.user_org_id())
    );

-- Audit Logs: read-only for org members, inserts via service_role only
CREATE POLICY audit_org_read ON audit_logs
    FOR SELECT USING (
        public.is_platform_admin() OR org_id = public.user_org_id()
    );

-- Permissions table: readable by all authenticated users (global constants)
ALTER TABLE permissions ENABLE ROW LEVEL SECURITY;
CREATE POLICY permissions_read_all ON permissions
    FOR SELECT USING (true);
