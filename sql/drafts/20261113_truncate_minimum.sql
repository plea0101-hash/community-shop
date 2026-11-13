-- DRAFT ONLY. Never execute on production without separate approval.
-- Targeted fix for the confirmed public.bookings TRUNCATE exposure only.
-- Does NOT grant DML, change RLS, revoke role membership or modify any data.
BEGIN;
REVOKE TRUNCATE ON TABLE public.bookings FROM PUBLIC,anon,authenticated;
DO $guard$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname IN ('anon','authenticated') AND (rolsuper OR rolbypassrls))
 OR pg_catalog.has_table_privilege('anon','public.bookings','TRUNCATE')
 OR pg_catalog.has_table_privilege('authenticated','public.bookings','TRUNCATE')
 THEN RAISE EXCEPTION 'truncate_source_unresolved_no_partial_fix'; END IF;
END;
$guard$;
COMMIT;
-- If a shared parent role is the source, inspect the read-only report first and
-- propose REVOKE TRUNCATE ON public.bookings FROM that exact grantee separately.
-- Do not guess a role name, revoke membership, use CASCADE, or revoke ALL globally.
-- Default ACL is separate: after identifying the actual creator and scope, review
-- an ALTER DEFAULT PRIVILEGES REVOKE TRUNCATE proposal; never rewrite unknown defaults.
