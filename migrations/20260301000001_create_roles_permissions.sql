-- Migration: roles, permissions, and role_permissions tables
-- Roles are org-scoped and soft-deletable.
-- Permissions are global constants.
-- hierarchy_level drives inheritance: higher level = more privilege.

CREATE TABLE roles (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id          UUID NOT NULL REFERENCES organizations(id),
    name            TEXT NOT NULL,
    hierarchy_level INTEGER NOT NULL DEFAULT 100,
    is_system       BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(org_id, name)
);

CREATE INDEX idx_roles_org ON roles(org_id) WHERE deleted_at IS NULL;

CREATE TRIGGER roles_updated_at
    BEFORE UPDATE ON roles
    FOR EACH ROW EXECUTE FUNCTION _set_updated_at();

CREATE TABLE permissions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key         TEXT NOT NULL UNIQUE,
    description TEXT NOT NULL DEFAULT '',
    category    TEXT NOT NULL DEFAULT 'general'
);

CREATE TABLE role_permissions (
    role_id       UUID NOT NULL REFERENCES roles(id),
    permission_id UUID NOT NULL REFERENCES permissions(id),
    PRIMARY KEY (role_id, permission_id)
);

INSERT INTO permissions (key, description, category) VALUES
    ('camera:live_view',     'View live camera feeds',               'camera'),
    ('camera:configure',     'Configure camera settings and tags',   'camera'),
    ('camera:manage',        'Add/remove cameras, manage credentials', 'camera'),
    ('violations:view',      'View violation records',               'violations'),
    ('violations:resolve',   'Confirm or reject violations',         'violations'),
    ('violations:export',    'Export violation data to CSV',          'violations'),
    ('users:invite',         'Invite new users to the organization', 'users'),
    ('users:manage',         'Edit user roles, soft-delete users',   'users'),
    ('roles:manage',         'Create/edit custom roles and permissions', 'roles'),
    ('org:settings',         'Manage organization settings',         'org'),
    ('audit:view',           'View audit logs',                      'audit'),
    ('sessions:view',        'View active user sessions',            'sessions');
