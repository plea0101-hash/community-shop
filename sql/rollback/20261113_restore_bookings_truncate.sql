-- DANGEROUS ROLLBACK DRAFT: reintroduces the confirmed exposure. Not routine repair.
-- Only after explicit approval and comparison with the saved pre-change ACL snapshot.
-- Applicable to the reported postgres-granted, no-GRANT-OPTION baseline only.
BEGIN;
DO $rollback$
BEGIN
 IF current_user<>'postgres' OR (SELECT relowner FROM pg_class WHERE oid='public.bookings'::regclass)<>'postgres'::regrole::oid THEN RAISE EXCEPTION 'rollback_requires_original_grantor_and_owner'; END IF;
 GRANT TRUNCATE ON TABLE public.bookings TO anon,authenticated;
END;
$rollback$;
COMMIT;
