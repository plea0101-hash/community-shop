-- DRAFT ONLY: no remote execution or deployment authorized.
-- Uses public.bookings exclusively. Supersedes the cs_ inventory draft; NEVER apply both.
-- Confirmed pending/confirmed [) contract; membership/payment and cancellation state still require review.
BEGIN;
CREATE TABLE public.booking_workflow_config (
 singleton boolean PRIMARY KEY CHECK(singleton),
 active_states text[] NOT NULL DEFAULT ARRAY['pending','confirmed']::text[] CHECK(active_states=ARRAY['pending','confirmed']::text[]),
 create_state text NOT NULL DEFAULT 'pending' CHECK(create_state='pending'), cancelled_state text,
 brand_state text, venue_state text NOT NULL DEFAULT 'available' CHECK(venue_state='available'), community_state text,
 membership_reviewed boolean NOT NULL DEFAULT false, payment_reviewed boolean NOT NULL DEFAULT false
);
-- Confirmed structural defaults are seeded; defaults pending are NOT eligibility approval.
-- Membership/payment gates and unconfirmed eligibility/cancellation mapping remain closed.
INSERT INTO public.booking_workflow_config(singleton) VALUES(true);
CREATE TABLE public.booking_brand_members (
 brand_id bigint REFERENCES public.brands(id), user_id uuid REFERENCES auth.users(id),
 can_manage boolean NOT NULL DEFAULT false, PRIMARY KEY(brand_id,user_id)
);
CREATE TABLE public.booking_community_members (
 community_id bigint REFERENCES public.communities(id), user_id uuid REFERENCES auth.users(id),
 can_manage boolean NOT NULL DEFAULT false, PRIMARY KEY(community_id,user_id)
);
CREATE TABLE public.booking_cancellation_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), booking_id bigint NOT NULL UNIQUE REFERENCES public.bookings(id),
 actor_id uuid NOT NULL REFERENCES auth.users(id), actor_side text NOT NULL CHECK(actor_side IN ('brand','community')),
 cancelled_at timestamptz NOT NULL, original_start_time timestamptz NOT NULL, original_end_time timestamptz NOT NULL,
 original_status text NOT NULL, reason text NOT NULL CHECK(length(reason)<=2000),
 hours_before_start numeric NOT NULL, timing text NOT NULL CHECK(timing IN ('general','late')),
 late_hours numeric NOT NULL DEFAULT 24 CHECK(late_hours=24),
 typhoon_status text NOT NULL CHECK(typhoon_status IN ('none','pending','verified','rejected')),
 evidence jsonb
);
CREATE TABLE public.booking_request_keys (
 actor_id uuid REFERENCES auth.users(id), request_key uuid, payload jsonb NOT NULL,
 booking_id bigint NOT NULL UNIQUE REFERENCES public.bookings(id),
 reapplied_from bigint REFERENCES public.bookings(id), PRIMARY KEY(actor_id,request_key)
);
CREATE TABLE public.booking_cancellation_reviews (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_id uuid NOT NULL REFERENCES public.booking_cancellation_events(id),
 reviewer_id uuid NOT NULL REFERENCES auth.users(id), reviewed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 decision text NOT NULL CHECK(decision IN ('pending','verified','rejected')),
 note text NOT NULL CHECK(length(btrim(note)) BETWEEN 1 AND 2000)
);
CREATE TABLE public.booking_event_notifications (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), recipient_id uuid NOT NULL REFERENCES auth.users(id),
 booking_id bigint NOT NULL REFERENCES public.bookings(id), event_key text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), read_at timestamptz,
 UNIQUE(recipient_id,event_key)
);
-- Durable organization-target outbox remains pending until a future worker resolves delivery.
CREATE TABLE public.booking_event_outbox (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_key text NOT NULL UNIQUE,
 booking_id bigint NOT NULL REFERENCES public.bookings(id),
 brand_id bigint REFERENCES public.brands(id), community_id bigint REFERENCES public.communities(id),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 delivery_state text NOT NULL DEFAULT 'pending' CHECK(delivery_state IN ('pending','delivered','failed')),
 CHECK((brand_id IS NULL)<>(community_id IS NULL))
);
CREATE FUNCTION public.booking_actor_is_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.platform_admins WHERE user_id=auth.uid());
$$;
CREATE FUNCTION public.booking_can_brand(p_brand bigint) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.booking_workflow_config WHERE singleton AND membership_reviewed) AND EXISTS(SELECT 1 FROM public.booking_brand_members WHERE brand_id=p_brand AND user_id=auth.uid() AND can_manage);
$$;
CREATE FUNCTION public.booking_can_community(p_community bigint) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.booking_workflow_config WHERE singleton AND membership_reviewed) AND EXISTS(SELECT 1 FROM public.booking_community_members WHERE community_id=p_community AND user_id=auth.uid() AND can_manage);
$$;
CREATE FUNCTION public.booking_can_read(p_booking bigint) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.bookings b JOIN public.venues v ON v.id=b.venue_id
 WHERE b.id=p_booking AND (public.booking_can_brand(b.brand_id) OR public.booking_can_community(v.community_id) OR public.booking_actor_is_admin()));
$$;
-- Fail closed: config must exactly match the existing two-state partial exclusion predicate.
-- Expected canonical text is based on the supplied real catalog shape, not inferred status names.
CREATE FUNCTION public.booking_checked_config() RETURNS public.booking_workflow_config LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.booking_workflow_config; pred text; idx text; exclusion text; default_expr text; table_name text;
BEGIN
 SELECT * INTO STRICT c FROM public.booking_workflow_config WHERE singleton;
 IF cardinality(c.active_states) IS DISTINCT FROM 2 OR c.create_state IS NULL OR c.cancelled_state IS NULL
 OR c.brand_state IS NULL OR c.venue_state IS NULL OR c.community_state IS NULL
 OR array_position(c.active_states,NULL) IS NOT NULL OR c.active_states[1]=c.active_states[2]
 OR NOT c.create_state=ANY(c.active_states) OR c.cancelled_state=ANY(c.active_states)
 THEN RAISE EXCEPTION 'production_contract_not_configured'; END IF;
 SELECT pg_catalog.pg_get_expr(i.indpred,i.indrelid),pg_catalog.pg_get_indexdef(i.indexrelid),pg_catalog.pg_get_constraintdef(k.oid,true)
 INTO pred,idx,exclusion FROM pg_catalog.pg_constraint k JOIN pg_catalog.pg_index i ON i.indexrelid=k.conindid
 WHERE k.conrelid='public.bookings'::regclass AND k.conname='bookings_no_overlap' AND k.contype='x' AND NOT k.condeferrable AND i.indisvalid AND i.indisready;
 IF exclusion IS NULL OR regexp_replace(exclusion,'\s','','g') <> regexp_replace(format('EXCLUDE USING gist (venue_id WITH =, tstzrange(start_time, end_time, ''[)''::text) WITH &&) WHERE (status = ANY (ARRAY[%L::text, %L::text]))',c.active_states[1],c.active_states[2]),'\s','','g') THEN RAISE EXCEPTION 'production_overlap_contract_mismatch'; END IF;
 IF pred IS NULL OR regexp_replace(pred,'\s','','g') <> regexp_replace(format('(status = ANY (ARRAY[%L::text, %L::text]))',c.active_states[1],c.active_states[2]),'\s','','g')
 OR position('tstzrange(start_time, end_time, ''[)''::text)' IN idx)=0
 THEN RAISE EXCEPTION 'production_overlap_contract_mismatch'; END IF;
 FOREACH table_name IN ARRAY ARRAY['bookings','brands','communities','venues'] LOOP
  SELECT pg_catalog.pg_get_expr(d.adbin,d.adrelid) INTO default_expr
  FROM pg_catalog.pg_attrdef d JOIN pg_catalog.pg_class r ON r.oid=d.adrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=r.relnamespace
  JOIN pg_catalog.pg_attribute a ON a.attrelid=r.oid AND a.attnum=d.adnum
  WHERE n.nspname='public' AND r.relname=table_name AND a.attname='status';
  IF default_expr IS DISTINCT FROM format('%L::text',CASE WHEN table_name='venues' THEN 'available' ELSE 'pending' END) THEN RAISE EXCEPTION 'production_status_default_mismatch'; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_constraint k WHERE k.conrelid='public.bookings'::regclass AND k.conname='bookings_valid_time' AND k.contype='c' AND k.convalidated AND regexp_replace(pg_catalog.pg_get_expr(k.conbin,k.conrelid),'[()\s]','','g')='end_time>start_time') THEN RAISE EXCEPTION 'production_time_check_mismatch'; END IF;
 IF NOT c.membership_reviewed THEN RAISE EXCEPTION 'membership_review_required'; END IF;
 IF NOT c.payment_reviewed THEN RAISE EXCEPTION 'payment_review_required'; END IF;
 RETURN c;
END;
$$;
CREATE FUNCTION public.booking_timing(p_start timestamptz,p_cancel timestamptz) RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT CASE WHEN p_start-p_cancel<=interval '24 hours' THEN 'late' ELSE 'general' END;
$$;
-- Shared implementation is private; callers never supply a status or actor identity.
CREATE FUNCTION public.booking_submit_internal(p_venue bigint,p_brand bigint,p_start timestamptz,p_end timestamptz,p_key uuid,p_source bigint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.booking_workflow_config; actor uuid:=auth.uid(); old public.bookings;
 v public.venues; source_venue bigint; payload jsonb; prior public.booking_request_keys; bid bigint;
BEGIN
 IF actor IS NULL OR p_key IS NULL THEN RAISE EXCEPTION 'authentication_and_request_key_required'; END IF;
 c:=public.booking_checked_config();
 payload:=jsonb_build_object('venue',p_venue,'brand',p_brand,'start',extract(epoch FROM p_start),'end',extract(epoch FROM p_end),'source',p_source);
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text||p_key::text,0));
 IF NOT public.booking_can_brand(p_brand) THEN RAISE EXCEPTION 'brand_membership_required'; END IF;
 SELECT * INTO prior FROM public.booking_request_keys WHERE actor_id=actor AND request_key=p_key;
 IF FOUND THEN
  IF prior.payload<>payload THEN RAISE EXCEPTION 'request_key_payload_mismatch'; END IF;
  RETURN prior.booking_id;
 END IF;
 IF NOT public.booking_can_brand(p_brand) THEN RAISE EXCEPTION 'brand_membership_required'; END IF;
 IF p_source IS NOT NULL THEN
  SELECT * INTO old FROM public.bookings WHERE id=p_source;
  IF NOT FOUND OR old.brand_id<>p_brand THEN RAISE EXCEPTION 'source_not_accessible'; END IF;
  source_venue:=old.venue_id;
 END IF;
 -- All our write RPCs lock venue rows in ascending order before booking rows.
 PERFORM id FROM public.venues WHERE id IN (p_venue,old.venue_id) ORDER BY id FOR UPDATE;
 IF p_source IS NOT NULL THEN
  SELECT * INTO old FROM public.bookings WHERE id=p_source FOR UPDATE;
  IF old.brand_id IS DISTINCT FROM p_brand OR old.venue_id IS DISTINCT FROM source_venue THEN RAISE EXCEPTION 'source_changed_retry'; END IF;
  IF old.status<>c.cancelled_state OR NOT EXISTS(SELECT 1 FROM public.booking_cancellation_events WHERE booking_id=old.id) THEN RAISE EXCEPTION 'cancel_first'; END IF;
 END IF;
 IF NOT public.booking_can_brand(p_brand) THEN RAISE EXCEPTION 'brand_membership_required'; END IF;
 SELECT * INTO v FROM public.venues WHERE id=p_venue;
 IF NOT FOUND OR v.status IS DISTINCT FROM c.venue_state THEN RAISE EXCEPTION 'venue_unavailable'; END IF;
 PERFORM id FROM public.brands WHERE id=p_brand AND status=c.brand_state FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'brand_not_eligible'; END IF;
 PERFORM id FROM public.communities WHERE id=v.community_id AND status=c.community_state FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'community_not_eligible'; END IF;
 IF p_start IS NULL OR p_end IS NULL OR NOT isfinite(p_start) OR NOT isfinite(p_end) OR p_end<=p_start OR p_start<=clock_timestamp() THEN RAISE EXCEPTION 'invalid_future_interval'; END IF;
 -- The existing exclusion constraint, not a SELECT availability check, is authoritative.
 INSERT INTO public.bookings(venue_id,brand_id,start_time,end_time,status)
 VALUES(p_venue,p_brand,p_start,p_end,c.create_state) RETURNING id INTO bid;
 INSERT INTO public.booking_request_keys VALUES(actor,p_key,payload,bid,p_source);
 INSERT INTO public.booking_event_outbox(event_key,booking_id,community_id) VALUES('requested:'||bid,bid,v.community_id);
 INSERT INTO public.booking_event_notifications(recipient_id,booking_id,event_key)
 SELECT user_id,bid,'requested:'||bid FROM public.booking_community_members WHERE community_id=v.community_id AND can_manage;
 RETURN bid;
END;
$$;
CREATE FUNCTION public.booking_request(p_venue bigint,p_brand bigint,p_start timestamptz,p_end timestamptz,p_key uuid)
RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT public.booking_submit_internal(p_venue,p_brand,p_start,p_end,p_key,NULL)::text;
$$;
CREATE FUNCTION public.booking_reapply(p_cancelled bigint,p_venue bigint,p_start timestamptz,p_end timestamptz,p_key uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE brand bigint;
BEGIN
 PERFORM public.booking_checked_config();
 SELECT brand_id INTO brand FROM public.bookings WHERE id=p_cancelled;
 IF NOT FOUND OR NOT public.booking_can_brand(brand) THEN RAISE EXCEPTION 'source_not_accessible'; END IF;
 RETURN public.booking_submit_internal(p_venue,brand,p_start,p_end,p_key,p_cancelled)::text;
END;
$$;
CREATE FUNCTION public.booking_cancel(p_booking bigint,p_reason text,p_typhoon jsonb DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE b public.bookings; initial_venue bigint; v public.venues; c public.booking_workflow_config;
 actor uuid:=auth.uid(); side text; eid uuid; t timestamptz; timing text; reason text:=btrim(coalesce(p_reason,'')); ad date; ed date;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
 c:=public.booking_checked_config();
 IF NOT public.booking_can_read(p_booking) THEN RAISE EXCEPTION 'booking_not_accessible'; END IF;
 SELECT venue_id INTO initial_venue FROM public.bookings WHERE id=p_booking;
 PERFORM id FROM public.venues WHERE id=initial_venue FOR UPDATE;
 SELECT * INTO b FROM public.bookings WHERE id=p_booking FOR UPDATE;
 SELECT * INTO v FROM public.venues WHERE id=b.venue_id;
 IF b.id IS NULL OR b.venue_id IS DISTINCT FROM initial_venue THEN RAISE EXCEPTION 'booking_not_accessible'; END IF;
 IF public.booking_can_brand(b.brand_id) AND public.booking_can_community(v.community_id) THEN RAISE EXCEPTION 'ambiguous_actor_side'; END IF;
 side:=CASE WHEN public.booking_can_brand(b.brand_id) THEN 'brand' WHEN public.booking_can_community(v.community_id) THEN 'community' END;
 IF side IS NULL THEN RAISE EXCEPTION 'booking_not_accessible'; END IF;
 IF b.status=c.cancelled_state THEN
  SELECT id INTO eid FROM public.booking_cancellation_events WHERE booking_id=b.id;
  IF eid IS NULL THEN RAISE EXCEPTION 'legacy_cancellation_missing_audit'; END IF;
  RETURN eid;
 END IF;
 IF NOT b.status=ANY(c.active_states) THEN RAISE EXCEPTION 'status_not_cancellable'; END IF;
 t:=clock_timestamp();
 IF b.start_time<=t THEN RAISE EXCEPTION 'activity_already_started'; END IF;
 timing:=public.booking_timing(b.start_time,t);
 IF length(reason)>2000 OR ((timing='late' OR p_typhoon IS NOT NULL) AND reason='') THEN RAISE EXCEPTION 'valid_reason_required'; END IF;
 IF p_typhoon IS NOT NULL THEN
  ad:=(p_typhoon->>'announced_on')::date; ed:=(p_typhoon->>'applicable_on')::date;
  IF jsonb_typeof(p_typhoon)<>'object' OR coalesce(p_typhoon->>'source_url','') !~ '^https://([a-zA-Z0-9-]+\.)*gov\.tw(/|$)'
  OR length(p_typhoon::text)>8000 OR ad IS NULL OR ad>(t AT TIME ZONE 'Asia/Taipei')::date
  OR ed IS DISTINCT FROM (b.start_time AT TIME ZONE 'Asia/Taipei')::date
  OR coalesce(p_typhoon->>'county','')<>ALL(ARRAY['臺北市','新北市','桃園市','臺中市','臺南市','高雄市','基隆市','新竹市','嘉義市','新竹縣','苗栗縣','彰化縣','南投縣','雲林縣','嘉義縣','屏東縣','宜蘭縣','花蓮縣','臺東縣','澎湖縣','金門縣','連江縣'])
  OR coalesce(p_typhoon->>'suspension','') NOT IN ('work','school','both') THEN RAISE EXCEPTION 'invalid_typhoon_evidence'; END IF;
 END IF;
 INSERT INTO public.booking_cancellation_events(booking_id,actor_id,actor_side,cancelled_at,original_start_time,original_end_time,original_status,reason,hours_before_start,timing,typhoon_status,evidence)
 VALUES(b.id,actor,side,t,b.start_time,b.end_time,b.status,reason,extract(epoch FROM(b.start_time-t))/3600,timing,CASE WHEN p_typhoon IS NULL THEN 'none' ELSE 'pending' END,CASE WHEN p_typhoon IS NULL THEN NULL ELSE jsonb_build_object('source_url',p_typhoon->>'source_url','announced_on',ad,'applicable_on',ed,'county',p_typhoon->>'county','suspension',p_typhoon->>'suspension') END) RETURNING id INTO eid;
 UPDATE public.bookings SET status=c.cancelled_state WHERE id=b.id;
 INSERT INTO public.booking_event_outbox(event_key,booking_id,brand_id,community_id)
 VALUES('cancelled:'||eid,b.id,CASE WHEN side='community' THEN b.brand_id END,CASE WHEN side='brand' THEN v.community_id END);
 INSERT INTO public.booking_event_notifications(recipient_id,booking_id,event_key)
 SELECT user_id,b.id,'cancelled:'||eid FROM (
 SELECT user_id FROM public.booking_community_members WHERE side='brand' AND community_id=v.community_id AND can_manage
 UNION SELECT user_id FROM public.booking_brand_members WHERE side='community' AND brand_id=b.brand_id AND can_manage
 ) recipients WHERE user_id<>actor;
 RETURN eid;
END;
$$;
CREATE FUNCTION public.booking_review_typhoon(p_event uuid,p_decision text,p_note text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.booking_cancellation_events; b public.bookings; community bigint; rid uuid;
BEGIN
 IF NOT public.booking_actor_is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
 PERFORM public.booking_checked_config();
 SELECT * INTO e FROM public.booking_cancellation_events WHERE id=p_event FOR UPDATE;
 IF NOT FOUND OR e.typhoon_status<>'pending' THEN RAISE EXCEPTION 'not_pending_review'; END IF;
 SELECT * INTO b FROM public.bookings WHERE id=e.booking_id;
 SELECT community_id INTO community FROM public.venues WHERE id=b.venue_id;
 IF public.booking_can_brand(b.brand_id) OR public.booking_can_community(community) THEN RAISE EXCEPTION 'independent_reviewer_required'; END IF;
 IF p_decision IS NULL OR p_decision NOT IN ('pending','verified','rejected') OR length(btrim(coalesce(p_note,''))) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'invalid_review'; END IF;
 INSERT INTO public.booking_cancellation_reviews(event_id,reviewer_id,decision,note) VALUES(e.id,auth.uid(),p_decision,btrim(p_note)) RETURNING id INTO rid;
 UPDATE public.booking_cancellation_events SET typhoon_status=p_decision WHERE id=e.id;
 INSERT INTO public.booking_event_outbox(event_key,booking_id,brand_id,community_id)
 VALUES('review:'||rid||':brand',b.id,b.brand_id,NULL),('review:'||rid||':community',b.id,NULL,community);
 INSERT INTO public.booking_event_notifications(recipient_id,booking_id,event_key)
 SELECT user_id,b.id,'review:'||rid FROM (
 SELECT user_id FROM public.booking_brand_members WHERE brand_id=b.brand_id AND can_manage
 UNION SELECT user_id FROM public.booking_community_members WHERE community_id=community AND can_manage
 ) recipients;
END;
$$;
CREATE VIEW public.booking_cancellation_classification WITH(security_invoker=true) AS
 SELECT id,booking_id,actor_id,actor_side,cancelled_at,timing,typhoon_status,
 CASE WHEN typhoon_status='verified' THEN 'typhoon_special' ELSE timing END AS classification,
 (timing='late' AND typhoon_status IN ('none','rejected')) AS counts_as_general_late
 FROM public.booking_cancellation_events;
-- RLS plus narrow RPC grants. No user-created memberships or direct booking mutations.
ALTER TABLE public.booking_event_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.booking_workflow_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.booking_brand_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.booking_community_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.booking_request_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.booking_cancellation_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.booking_cancellation_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.booking_event_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY booking_participant_read ON public.bookings FOR SELECT TO authenticated USING(public.booking_can_read(id));
-- Existing permissive policies combine with OR; do not let an unreviewed legacy
-- policy bypass the membership gate or expand the new participant SELECT grant.
CREATE POLICY booking_participant_guard ON public.bookings AS RESTRICTIVE FOR SELECT TO authenticated USING(public.booking_can_read(id));
CREATE POLICY booking_event_read ON public.booking_cancellation_events FOR SELECT TO authenticated USING(public.booking_can_read(booking_id));
CREATE POLICY booking_review_read ON public.booking_cancellation_reviews FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.booking_cancellation_events e WHERE e.id=event_id));
CREATE POLICY booking_notification_read ON public.booking_event_notifications FOR SELECT TO authenticated USING(recipient_id=auth.uid());
-- TRUNCATE bypasses RLS. Explicitly remove all direct table privileges, then grant reads only.
REVOKE TRUNCATE,TRIGGER,REFERENCES,MAINTAIN ON public.bookings,public.brands,public.venues,public.communities FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.bookings FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.bookings TO authenticated;
REVOKE ALL ON public.booking_event_outbox,public.booking_workflow_config,public.booking_brand_members,public.booking_community_members,public.booking_request_keys,public.booking_cancellation_events,public.booking_cancellation_reviews,public.booking_event_notifications FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.booking_cancellation_classification FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.booking_cancellation_classification,public.booking_cancellation_events,public.booking_cancellation_reviews,public.booking_event_notifications TO authenticated;
REVOKE ALL ON FUNCTION public.booking_actor_is_admin(),public.booking_can_brand(bigint),public.booking_can_community(bigint),public.booking_can_read(bigint),public.booking_checked_config(),public.booking_timing(timestamptz,timestamptz),public.booking_submit_internal(bigint,bigint,timestamptz,timestamptz,uuid,bigint),public.booking_request(bigint,bigint,timestamptz,timestamptz,uuid),public.booking_reapply(bigint,bigint,timestamptz,timestamptz,uuid),public.booking_cancel(bigint,text,jsonb),public.booking_review_typhoon(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.booking_can_read(bigint),public.booking_request(bigint,bigint,timestamptz,timestamptz,uuid),public.booking_reapply(bigint,bigint,timestamptz,timestamptz,uuid),public.booking_cancel(bigint,text,jsonb),public.booking_review_typhoon(uuid,text,text) TO authenticated;
-- An inherited privilege is not removed by revoking a direct grant. Fail installation
-- rather than claiming RPC-only protection when a parent role still permits writes.
DO $guard$
DECLARE r text; t text; privilege text;
BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname=r AND (rolsuper OR rolbypassrls)) THEN RAISE EXCEPTION 'unsafe_client_role'; END IF;
  FOREACH privilege IN ARRAY ARRAY['INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER','REFERENCES','MAINTAIN'] LOOP
   IF pg_catalog.has_table_privilege(r,'public.bookings',privilege) THEN RAISE EXCEPTION 'inherited_booking_write_privilege_remains'; END IF;
  END LOOP;
  FOREACH t IN ARRAY ARRAY['public.booking_workflow_config','public.booking_brand_members','public.booking_community_members','public.booking_request_keys','public.booking_cancellation_events','public.booking_cancellation_reviews','public.booking_event_notifications','public.booking_event_outbox'] LOOP
   FOREACH privilege IN ARRAY ARRAY['INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER','REFERENCES','MAINTAIN'] LOOP
    IF pg_catalog.has_table_privilege(r,t,privilege) THEN RAISE EXCEPTION 'inherited_audit_or_membership_write_privilege_remains'; END IF;
   END LOOP;
  END LOOP;
  FOREACH t IN ARRAY ARRAY['public.brands','public.communities','public.venues'] LOOP
   FOREACH privilege IN ARRAY ARRAY['TRUNCATE','TRIGGER','REFERENCES','MAINTAIN'] LOOP
    IF pg_catalog.has_table_privilege(r,t,privilege) THEN RAISE EXCEPTION 'inherited_unsafe_table_privilege_remains'; END IF;
   END LOOP;
  END LOOP;
 END LOOP;
END;
$guard$;
COMMIT;
