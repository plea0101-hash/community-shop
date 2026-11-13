-- Synthetic reconstruction of reported ACL sources. Other privileges are deliberate
-- local sentinels, NOT a claim that production default ACL includes ALL privileges.
CREATE ROLE service_role;
CREATE ROLE supabase_admin;
GRANT USAGE,CREATE ON SCHEMA public TO supabase_admin;
GRANT ALL ON TABLE public.bookings TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon,authenticated,service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon,authenticated,service_role;
