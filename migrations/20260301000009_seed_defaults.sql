-- Migration: seed default organization, roles, permission assignments, and backfill org_id.
-- Platform Admin user is created manually post-migration (credentials must not be in VCS).

-- ── Default Organization ─────────────────────────────────────────────────────

INSERT INTO organizations (id, name, slug) VALUES
    ('00000000-0000-0000-0000-000000000001', 'Default HOA', 'default-hoa')
ON CONFLICT (id) DO NOTHING;

-- ── Default Roles ────────────────────────────────────────────────────────────

INSERT INTO roles (id, org_id, name, hierarchy_level, is_system) VALUES
    ('00000000-0000-0000-0000-000000000010',
     '00000000-0000-0000-0000-000000000001', 'Guard',        100, TRUE),
    ('00000000-0000-0000-0000-000000000020',
     '00000000-0000-0000-0000-000000000001', 'Senior Guard', 200, TRUE),
    ('00000000-0000-0000-0000-000000000030',
     '00000000-0000-0000-0000-000000000001', 'Manager',      300, TRUE)
ON CONFLICT (id) DO NOTHING;

-- ── Permission Assignments ───────────────────────────────────────────────────

-- Guard: view-only access
INSERT INTO role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000010', id FROM permissions
WHERE key IN ('camera:live_view', 'violations:view')
ON CONFLICT DO NOTHING;

-- Senior Guard: Guard + configure cameras, resolve/export violations
INSERT INTO role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000020', id FROM permissions
WHERE key IN (
    'camera:live_view', 'camera:configure',
    'violations:view', 'violations:resolve', 'violations:export'
)
ON CONFLICT DO NOTHING;

-- Manager: all permissions
INSERT INTO role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000030', id FROM permissions
ON CONFLICT DO NOTHING;

-- ── Backfill org_id on existing tables ───────────────────────────────────────

UPDATE cameras SET org_id = '00000000-0000-0000-0000-000000000001'
WHERE org_id IS NULL;

UPDATE violations SET org_id = '00000000-0000-0000-0000-000000000001'
WHERE org_id IS NULL;

-- ── Enforce NOT NULL after backfill ──────────────────────────────────────────

ALTER TABLE cameras ALTER COLUMN org_id SET NOT NULL;
ALTER TABLE violations ALTER COLUMN org_id SET NOT NULL;
