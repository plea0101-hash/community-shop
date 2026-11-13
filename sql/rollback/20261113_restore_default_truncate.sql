-- DANGEROUS ROLLBACK DRAFT: restores future public-table exposure for both creators.
-- Compare the saved baseline first; this assumes the reported no-GRANT-OPTION grants.
-- Does NOT retroactively change tables created while the fix was in effect.
BEGIN;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT TRUNCATE ON TABLES TO anon,authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT TRUNCATE ON TABLES TO anon,authenticated;
COMMIT;
