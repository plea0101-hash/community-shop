-- DRAFT ONLY: no production execution authorized.
-- Confirmed source: postgres directly grants TRUNCATE to anon/authenticated;
-- bookings owner=postgres, no membership paths observed. ONLY this table/privilege.
BEGIN;
DO $fix$
DECLARE before_acl jsonb; after_acl jsonb; before_maintenance jsonb; after_maintenance jsonb;
BEGIN
 IF (SELECT relowner FROM pg_catalog.pg_class WHERE oid='public.bookings'::regclass) IS DISTINCT FROM 'postgres'::regrole::oid THEN RAISE EXCEPTION 'bookings_owner_drift'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='service_role') THEN RAISE EXCEPTION 'required_maintenance_role_missing'; END IF;
 -- Capture every unrelated ACL entry, including grantor and grant option.
 SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.grantor,a.grantee,a.privilege_type),'[]') INTO before_acl
 FROM pg_catalog.pg_class c CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
 WHERE c.oid='public.bookings'::regclass AND NOT(a.privilege_type='TRUNCATE' AND a.grantee IN ('anon'::regrole::oid,'authenticated'::regrole::oid));
 SELECT jsonb_agg(jsonb_build_array(r,p,pg_catalog.has_table_privilege(r,'public.bookings',p)) ORDER BY r,p) INTO before_maintenance
 FROM unnest(ARRAY['postgres','service_role']) r CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p;
 REVOKE TRUNCATE ON TABLE public.bookings FROM anon,authenticated;
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname IN ('anon','authenticated') AND (rolsuper OR rolbypassrls))
 OR pg_catalog.has_table_privilege('anon','public.bookings','TRUNCATE') OR pg_catalog.has_table_privilege('authenticated','public.bookings','TRUNCATE')
 THEN RAISE EXCEPTION 'truncate_source_unresolved_no_partial_fix'; END IF;
 SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.grantor,a.grantee,a.privilege_type),'[]') INTO after_acl
 FROM pg_catalog.pg_class c CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
 WHERE c.oid='public.bookings'::regclass AND NOT(a.privilege_type='TRUNCATE' AND a.grantee IN ('anon'::regrole::oid,'authenticated'::regrole::oid));
 SELECT jsonb_agg(jsonb_build_array(r,p,pg_catalog.has_table_privilege(r,'public.bookings',p)) ORDER BY r,p) INTO after_maintenance
 FROM unnest(ARRAY['postgres','service_role']) r CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p;
 IF before_acl IS DISTINCT FROM after_acl OR before_maintenance IS DISTINCT FROM after_maintenance THEN RAISE EXCEPTION 'unrelated_or_maintenance_acl_changed'; END IF;
END;
$fix$;
COMMIT;
-- Does not revoke PUBLIC/shared parent roles, change RLS/DML or default ACL.
-- Unexpected remaining sources cause rollback, not a broader automatic revoke.
