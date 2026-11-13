-- EXECUTION LIMIT: docs-only update; Codex must not execute production SQL.
-- BLOCKED for current postgres: no MEMBER/USAGE/SET authority for supabase_admin.
-- Keep both creator statements atomic. Do not extract/run postgres-only SQL,
-- auto SET ROLE, GRANT membership, elevate privileges or probe production DCL.
-- Requires platform-supported authorized operator and separate stage-B approval.
-- DRAFT ONLY. Separate approval required. Future public tables only, not existing tables.
-- Operator must be authorized to alter BOTH creators' default privileges.
BEGIN;
DO $fix$
DECLARE before_acl jsonb; after_acl jsonb;
BEGIN
 -- Preserve ALL non-target default ACL entries, every creator/schema/object type.
 SELECT COALESCE(jsonb_agg(jsonb_build_array(d.defaclrole,d.defaclnamespace,d.defaclobjtype,a.grantor,a.grantee,a.privilege_type,a.is_grantable)
 ORDER BY d.defaclrole,d.defaclnamespace,d.defaclobjtype,a.grantor,a.grantee,a.privilege_type),'[]') INTO before_acl
 FROM pg_catalog.pg_default_acl d CROSS JOIN LATERAL pg_catalog.aclexplode(d.defaclacl) a
 WHERE NOT(d.defaclrole IN ('postgres'::regrole::oid,'supabase_admin'::regrole::oid) AND d.defaclnamespace='public'::regnamespace::oid AND d.defaclobjtype='r' AND a.grantee IN ('anon'::regrole::oid,'authenticated'::regrole::oid) AND a.privilege_type='TRUNCATE');
 ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE TRUNCATE ON TABLES FROM anon,authenticated;
 ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public REVOKE TRUNCATE ON TABLES FROM anon,authenticated;
 -- Per-schema REVOKE cannot override a GLOBAL GRANT or an inherited/PUBLIC grant.
 IF EXISTS(
 SELECT 1 FROM pg_catalog.pg_default_acl d CROSS JOIN LATERAL pg_catalog.aclexplode(d.defaclacl) a
 CROSS JOIN pg_catalog.pg_roles client
 WHERE client.rolname IN ('anon','authenticated') AND d.defaclrole IN ('postgres'::regrole::oid,'supabase_admin'::regrole::oid)
 AND d.defaclobjtype='r' AND d.defaclnamespace IN (0,'public'::regnamespace::oid) AND a.privilege_type='TRUNCATE'
 AND CASE WHEN a.grantee=0 THEN true ELSE pg_catalog.pg_has_role(client.oid,a.grantee,'USAGE') END
 ) OR EXISTS(SELECT 1 FROM pg_catalog.pg_roles client WHERE client.rolname IN ('anon','authenticated') AND (client.rolsuper OR client.rolbypassrls OR pg_catalog.pg_has_role(client.oid,'postgres'::regrole,'USAGE') OR pg_catalog.pg_has_role(client.oid,'supabase_admin'::regrole,'USAGE')))
 THEN RAISE EXCEPTION 'default_acl_truncate_source_unresolved'; END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_array(d.defaclrole,d.defaclnamespace,d.defaclobjtype,a.grantor,a.grantee,a.privilege_type,a.is_grantable)
 ORDER BY d.defaclrole,d.defaclnamespace,d.defaclobjtype,a.grantor,a.grantee,a.privilege_type),'[]') INTO after_acl
 FROM pg_catalog.pg_default_acl d CROSS JOIN LATERAL pg_catalog.aclexplode(d.defaclacl) a
 WHERE NOT(d.defaclrole IN ('postgres'::regrole::oid,'supabase_admin'::regrole::oid) AND d.defaclnamespace='public'::regnamespace::oid AND d.defaclobjtype='r' AND a.grantee IN ('anon'::regrole::oid,'authenticated'::regrole::oid) AND a.privilege_type='TRUNCATE');
 IF before_acl IS DISTINCT FROM after_acl THEN RAISE EXCEPTION 'unrelated_default_acl_changed'; END IF;
END;
$fix$;
COMMIT;
-- Never targets service_role, postgres, owners, other schemas/creators or non-TRUNCATE grants.
