-- READ ONLY, metadata only. To be reviewed by the actual authorized execution identity.
-- This is a catalog estimate, NOT permission to execute DCL and NOT proof that a
-- managed Supabase platform permits changing supabase_admin defaults.
WITH actor AS (
 SELECT oid,rolname,rolsuper,rolbypassrls FROM pg_catalog.pg_roles WHERE rolname=current_user
), creators AS (
 SELECT oid,rolname FROM pg_catalog.pg_roles WHERE rolname IN ('postgres','supabase_admin')
), target AS (
 SELECT relowner FROM pg_catalog.pg_class WHERE oid='public.bookings'::regclass
)
SELECT jsonb_build_object(
 'session_identity',session_user,'active_identity',current_user,
 'active_is_superuser',(SELECT rolsuper FROM actor),
 'bookings_owner',(SELECT pg_catalog.pg_get_userbyid(relowner) FROM target),
 'can_use_owner_privileges',(SELECT pg_catalog.pg_has_role(a.oid,t.relowner,'USAGE') FROM actor a CROSS JOIN target t),
 'has_truncate_grant_option',pg_catalog.has_table_privilege(current_user,'public.bookings','TRUNCATE WITH GRANT OPTION'),
 'creator_authority',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'creator',c.rolname,'is_current_identity',c.oid=a.oid,
 'member',pg_catalog.pg_has_role(a.oid,c.oid,'MEMBER'),
 'usable_without_set_role',pg_catalog.pg_has_role(a.oid,c.oid,'USAGE'),
 'set_role_allowed_by_catalog',pg_catalog.pg_has_role(a.oid,c.oid,'SET'),
 'current_identity_catalog_candidate',a.rolsuper OR pg_catalog.pg_has_role(a.oid,c.oid,'USAGE')
 ) ORDER BY c.rolname) FROM creators c CROSS JOIN actor a),'[]'::jsonb),
 'catalog_estimate_only',true,
 'managed_platform_authorization_still_required',true,
 'production_dcl_probe_authorized',false
) AS truncate_executor_preflight;
-- Do not test authority by ALTER/GRANT/REVOKE followed by ROLLBACK in production.
-- Do not automatically SET ROLE or grant membership. Escalate to an authorized
-- project/platform operator if the active identity cannot alter both creators.
