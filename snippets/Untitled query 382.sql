INSERT INTO users (auth_id, org_id, role_id, email, display_name, is_platform_admin)
VALUES (
  '5012e4dc-77b7-4dcb-9313-f7ef2ef286ea',
  '00000000-0000-0000-0000-000000000001',  -- Default HOA org
  '00000000-0000-0000-0000-000000000030',  -- Manager role
  'admin@yourdomain.com',
  'Platform Admin',
  TRUE
);

SELECT id, email FROM auth.users;