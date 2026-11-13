-- READ ONLY: run unchanged before and after EACH separately approved fix.
-- Save the complete BEFORE JSON outside the DB for comparison/rollback grant options.
-- Reads metadata only; never creates canary tables or reads bookings rows.
WITH
b AS (SELECT * FROM pg_catalog.pg_class WHERE oid='public.bookings'::regclass),
clients AS (SELECT oid,rolname FROM pg_catalog.pg_roles WHERE rolname IN ('anon','authenticated')),
creators AS (SELECT oid,rolname FROM pg_catalog.pg_roles WHERE rolname IN ('postgres','supabase_admin')),
table_acl AS (
 SELECT a.* FROM b CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(b.relacl,pg_catalog.acldefault('r',b.relowner))) a
),
default_acl AS (
 SELECT d.defaclrole,d.defaclnamespace,d.defaclobjtype,a.* FROM pg_catalog.pg_default_acl d
 CROSS JOIN LATERAL pg_catalog.aclexplode(d.defaclacl) a
 WHERE d.defaclrole IN (SELECT oid FROM creators) AND d.defaclnamespace IN (0,'public'::regnamespace::oid) AND d.defaclobjtype='r'
)
SELECT jsonb_build_object(
 'bookings_owner',(SELECT pg_catalog.pg_get_userbyid(relowner) FROM b),
 'bookings_rls',(SELECT jsonb_build_object('enabled',relrowsecurity,'forced',relforcerowsecurity) FROM b),
 'bookings_acl',COALESCE((SELECT jsonb_agg(jsonb_build_object('grantor',pg_catalog.pg_get_userbyid(grantor),'grantee',CASE WHEN grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(grantee)::text END,'privilege',privilege_type,'grantable',is_grantable) ORDER BY grantor,grantee,privilege_type) FROM table_acl),'[]'::jsonb),
 'effective_permissions',COALESCE((SELECT jsonb_agg(jsonb_build_object('role',r.rolname,'privilege',p,'allowed',pg_catalog.has_table_privilege(r.oid,'public.bookings',p)) ORDER BY r.rolname,p) FROM pg_catalog.pg_roles r CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p WHERE r.rolname IN ('anon','authenticated','postgres','service_role')),'[]'::jsonb),
 'default_acl',COALESCE((SELECT jsonb_agg(jsonb_build_object('creator',pg_catalog.pg_get_userbyid(defaclrole),'schema',CASE WHEN defaclnamespace=0 THEN '<global>' ELSE 'public' END,'grantor',pg_catalog.pg_get_userbyid(grantor),'grantee',CASE WHEN grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(grantee)::text END,'privilege',privilege_type,'grantable',is_grantable) ORDER BY defaclrole,defaclnamespace,grantor,grantee,privilege_type) FROM default_acl),'[]'::jsonb),
 'rollback_from_snapshot',jsonb_build_object(
 'bookings',COALESCE((SELECT jsonb_agg(jsonb_build_object('run_as_grantor',pg_catalog.pg_get_userbyid(grantor),'sql',format('GRANT TRUNCATE ON TABLE public.bookings TO %I%s;',pg_catalog.pg_get_userbyid(grantee),CASE WHEN is_grantable THEN ' WITH GRANT OPTION' ELSE '' END)) ORDER BY grantee) FROM table_acl WHERE grantee IN ('anon'::regrole::oid,'authenticated'::regrole::oid) AND privilege_type='TRUNCATE'),'[]'::jsonb),
 'defaults',COALESCE((SELECT jsonb_agg(jsonb_build_object('creator',pg_catalog.pg_get_userbyid(defaclrole),'grantor',pg_catalog.pg_get_userbyid(grantor),'sql',format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public GRANT TRUNCATE ON TABLES TO %I%s;',pg_catalog.pg_get_userbyid(defaclrole),pg_catalog.pg_get_userbyid(grantee),CASE WHEN is_grantable THEN ' WITH GRANT OPTION' ELSE '' END)) ORDER BY defaclrole,grantee) FROM default_acl WHERE defaclnamespace='public'::regnamespace::oid AND grantee IN ('anon'::regrole::oid,'authenticated'::regrole::oid) AND privilege_type='TRUNCATE'),'[]'::jsonb)
 ),
 'checks',jsonb_build_object(
 'bookings_clients_cannot_truncate',NOT EXISTS(SELECT 1 FROM clients WHERE pg_catalog.has_table_privilege(oid,'public.bookings','TRUNCATE')),
 'both_creators_present',(SELECT count(*)=2 FROM creators),
 'maintenance_roles_present',(SELECT count(*)=2 FROM pg_catalog.pg_roles WHERE rolname IN ('postgres','service_role')),
 'future_public_client_truncate_sources_absent',NOT EXISTS(SELECT 1 FROM default_acl a CROSS JOIN clients c WHERE a.privilege_type='TRUNCATE' AND CASE WHEN a.grantee=0 THEN true ELSE pg_catalog.pg_has_role(c.oid,a.grantee,'USAGE') END)
 AND NOT EXISTS(SELECT 1 FROM clients c CROSS JOIN creators r WHERE pg_catalog.pg_has_role(c.oid,r.oid,'USAGE'))
 )
) AS truncate_fix_verification;
