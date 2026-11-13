-- SUPERSEDED inventory prototype. Do not apply with production booking RPC draft.
-- DRAFT ONLY. Do not execute against Supabase before explicit approval.
-- Additive module schema. No changes to existing public.bookings or existing data.
-- Requires reviewed integration of production bookings/identity/slot lifecycle first.
BEGIN;
CREATE TABLE public.cs_admins (user_id uuid PRIMARY KEY REFERENCES auth.users(id));
CREATE TABLE public.cs_policy (
 id boolean PRIMARY KEY DEFAULT true CHECK(id),
 late_hours numeric CHECK (late_hours > 0 AND late_hours < 8760)
);
INSERT INTO public.cs_policy(id,late_hours) VALUES (true,24); -- user confirmed: <=24 hours is late; no automatic penalties
CREATE TABLE public.cs_slots (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 venue_ref text NOT NULL,
 community_user_id uuid NOT NULL REFERENCES auth.users(id),
 starts_at timestamptz NOT NULL,
 ends_at timestamptz NOT NULL CHECK (ends_at > starts_at),
 UNIQUE(venue_ref, starts_at)
);
-- Slot creation and overlap checking belong to the reviewed booking integration.
CREATE TABLE public.cs_bookings (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 source_booking_ref text UNIQUE,
 slot_id uuid NOT NULL REFERENCES public.cs_slots(id),
 vendor_user_id uuid NOT NULL REFERENCES auth.users(id),
 community_user_id uuid NOT NULL REFERENCES auth.users(id),
 label text NOT NULL CHECK(length(label) BETWEEN 1 AND 200),
 status text NOT NULL CHECK(status IN ('pending','confirmed','cancelled')),
 reapplied_from uuid REFERENCES public.cs_bookings(id),
 requested_by uuid REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(vendor_user_id <> community_user_id)
);
CREATE UNIQUE INDEX cs_one_live_booking_per_slot ON public.cs_bookings(slot_id) WHERE status IN ('pending','confirmed');
CREATE TABLE public.cs_cancellations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 booking_id uuid NOT NULL UNIQUE REFERENCES public.cs_bookings(id),
 actor_id uuid NOT NULL REFERENCES auth.users(id),
 actor_side text NOT NULL CHECK(actor_side IN ('vendor','community')),
 cancelled_at timestamptz NOT NULL,
 original_starts_at timestamptz NOT NULL,
 original_ends_at timestamptz NOT NULL,
 original_status text NOT NULL,
 reason text NOT NULL CHECK(length(reason) <= 2000),
 hours_before_start numeric NOT NULL,
 late_hours_snapshot numeric,
 timing text NOT NULL CHECK(timing IN ('general','late','unclassified')),
 status text NOT NULL DEFAULT 'cancelled' CHECK(status='cancelled'),
 typhoon_status text NOT NULL CHECK(typhoon_status IN ('none','pending','verified','rejected')),
 source_url text,
 announced_on date,
 applicable_on date,
 county text,
 suspension text CHECK(suspension IN ('work','school','both')),
 CHECK(typhoon_status='none' OR (source_url IS NOT NULL AND announced_on IS NOT NULL AND applicable_on IS NOT NULL AND county IS NOT NULL AND suspension IS NOT NULL))
);
CREATE TABLE public.cs_typhoon_reviews (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 cancellation_id uuid NOT NULL REFERENCES public.cs_cancellations(id),
 reviewer_id uuid NOT NULL REFERENCES auth.users(id),
 reviewed_at timestamptz NOT NULL DEFAULT now(),
 decision text NOT NULL CHECK(decision IN ('verified','rejected','pending')),
 note text NOT NULL CHECK(length(btrim(note)) BETWEEN 1 AND 2000)
);
CREATE TABLE public.cs_notifications (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 recipient_id uuid NOT NULL REFERENCES auth.users(id),
 booking_id uuid NOT NULL REFERENCES public.cs_bookings(id),
 cancellation_id uuid REFERENCES public.cs_cancellations(id),
 kind text NOT NULL CHECK(kind IN ('cancelled','typhoon_review','reapplied')),
 created_at timestamptz NOT NULL DEFAULT now(),
 read_at timestamptz
);
CREATE INDEX cs_cancellation_actor_time ON public.cs_cancellations(actor_id,cancelled_at);
CREATE INDEX cs_notification_recipient ON public.cs_notifications(recipient_id,created_at);

CREATE FUNCTION public.cs_is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
 SELECT EXISTS(SELECT 1 FROM public.cs_admins WHERE user_id=auth.uid());
$$;
ALTER TABLE public.cs_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_cancellations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_typhoon_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY cs_admin_self ON public.cs_admins FOR SELECT TO authenticated USING(user_id=auth.uid());
CREATE POLICY cs_policy_read ON public.cs_policy FOR SELECT TO authenticated USING(true);
CREATE POLICY cs_slot_read ON public.cs_slots FOR SELECT TO authenticated USING(true);
CREATE POLICY cs_booking_read ON public.cs_bookings FOR SELECT TO authenticated
 USING(auth.uid() IN (vendor_user_id,community_user_id) OR public.cs_is_admin());
CREATE POLICY cs_cancel_read ON public.cs_cancellations FOR SELECT TO authenticated
 USING(EXISTS(SELECT 1 FROM public.cs_bookings b WHERE b.id=booking_id));
CREATE POLICY cs_review_read ON public.cs_typhoon_reviews FOR SELECT TO authenticated
 USING(EXISTS(SELECT 1 FROM public.cs_cancellations c WHERE c.id=cancellation_id));
CREATE POLICY cs_notification_read ON public.cs_notifications FOR SELECT TO authenticated USING(recipient_id=auth.uid());

CREATE FUNCTION public.cs_cancel_booking(p_booking_id uuid,p_reason text,p_typhoon jsonb DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
 b public.cs_bookings; s public.cs_slots; cid uuid; actor uuid := auth.uid();
 t timestamptz; h numeric; threshold numeric; classification text;
 side text; reason text := btrim(coalesce(p_reason,''));
 ad date; ed date;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
 SELECT * INTO b FROM public.cs_bookings WHERE id=p_booking_id FOR UPDATE;
 IF NOT FOUND OR actor NOT IN (b.vendor_user_id,b.community_user_id) THEN RAISE EXCEPTION 'booking_not_accessible'; END IF;
 IF b.status='cancelled' THEN
   SELECT id INTO cid FROM public.cs_cancellations WHERE booking_id=b.id;
   IF cid IS NULL THEN RAISE EXCEPTION 'cancellation_record_missing'; END IF;
   RETURN cid; -- idempotent duplicate; no duplicate release or notification
 END IF;
 IF b.status NOT IN ('confirmed','pending') THEN RAISE EXCEPTION 'booking_not_cancellable'; END IF;
 SELECT * INTO STRICT s FROM public.cs_slots WHERE id=b.slot_id FOR UPDATE;
 t := clock_timestamp(); -- classify only after acquiring the locks
 IF t >= s.starts_at THEN RAISE EXCEPTION 'activity_already_started'; END IF;
 SELECT late_hours INTO threshold FROM public.cs_policy WHERE id=true;
 h := extract(epoch FROM (s.starts_at-t))/3600;
 classification := CASE WHEN threshold IS NULL THEN 'unclassified' WHEN h <= threshold THEN 'late' ELSE 'general' END;
 IF length(reason)>2000 THEN RAISE EXCEPTION 'reason_too_long'; END IF;
 -- Conservative while threshold is unknown: require reason, without assigning a violation.
 IF (classification IN ('late','unclassified') OR p_typhoon IS NOT NULL) AND reason='' THEN RAISE EXCEPTION 'reason_required'; END IF;
 IF p_typhoon IS NOT NULL THEN
   IF jsonb_typeof(p_typhoon)<>'object' THEN RAISE EXCEPTION 'invalid_typhoon_evidence'; END IF;
   ad := (p_typhoon->>'announced_on')::date;
   ed := (p_typhoon->>'applicable_on')::date;
   IF coalesce(p_typhoon->>'source_url','') !~ '^https://([a-zA-Z0-9-]+\.)*gov\.tw(/|$)'
     OR length(p_typhoon->>'source_url')>2000
     OR ad IS NULL OR ad > (t AT TIME ZONE 'Asia/Taipei')::date
     OR ed IS DISTINCT FROM (s.starts_at AT TIME ZONE 'Asia/Taipei')::date
     OR coalesce(p_typhoon->>'county','') <> ALL(ARRAY['臺北市','新北市','桃園市','臺中市','臺南市','高雄市','基隆市','新竹市','嘉義市','新竹縣','苗栗縣','彰化縣','南投縣','雲林縣','嘉義縣','屏東縣','宜蘭縣','花蓮縣','臺東縣','澎湖縣','金門縣','連江縣'])
     OR coalesce(p_typhoon->>'suspension','') NOT IN ('work','school','both')
   THEN RAISE EXCEPTION 'invalid_typhoon_evidence'; END IF;
 END IF;
 side := CASE WHEN actor=b.vendor_user_id THEN 'vendor' ELSE 'community' END;
 INSERT INTO public.cs_cancellations(booking_id,actor_id,actor_side,cancelled_at,original_starts_at,original_ends_at,original_status,reason,hours_before_start,late_hours_snapshot,timing,typhoon_status,source_url,announced_on,applicable_on,county,suspension)
 VALUES(b.id,actor,side,t,s.starts_at,s.ends_at,b.status,reason,h,threshold,classification,
 CASE WHEN p_typhoon IS NULL THEN 'none' ELSE 'pending' END,
 p_typhoon->>'source_url',ad,ed,p_typhoon->>'county',p_typhoon->>'suspension') RETURNING id INTO cid;
 UPDATE public.cs_bookings SET status='cancelled' WHERE id=b.id;
 -- Partial unique index releases this module's slot in this same transaction.
 INSERT INTO public.cs_notifications(recipient_id,booking_id,cancellation_id,kind)
 VALUES(CASE WHEN side='vendor' THEN b.community_user_id ELSE b.vendor_user_id END,b.id,cid,'cancelled');
 RETURN cid;
END;
$$;

CREATE FUNCTION public.cs_review_typhoon(p_cancellation_id uuid,p_verified boolean,p_note text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE c public.cs_cancellations; b public.cs_bookings; decision text;
BEGIN
 IF NOT public.cs_is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
 IF length(btrim(coalesce(p_note,''))) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'review_note_required'; END IF;
 SELECT * INTO c FROM public.cs_cancellations WHERE id=p_cancellation_id FOR UPDATE;
 IF NOT FOUND OR c.typhoon_status<>'pending' THEN RAISE EXCEPTION 'not_pending_review'; END IF;
 SELECT * INTO STRICT b FROM public.cs_bookings WHERE id=c.booking_id;
 IF auth.uid() IN (b.vendor_user_id,b.community_user_id) THEN RAISE EXCEPTION 'independent_reviewer_required'; END IF;
 -- Human reviewer must verify official government typhoon closure and the recorded dates.
 decision := CASE WHEN p_verified IS NULL THEN 'pending' WHEN p_verified THEN 'verified' ELSE 'rejected' END;
 INSERT INTO public.cs_typhoon_reviews(cancellation_id,reviewer_id,decision,note) VALUES(c.id,auth.uid(),decision,btrim(p_note));
 UPDATE public.cs_cancellations SET typhoon_status=decision WHERE id=c.id;
 INSERT INTO public.cs_notifications(recipient_id,booking_id,cancellation_id,kind)
 VALUES(b.vendor_user_id,b.id,c.id,'typhoon_review'),(b.community_user_id,b.id,c.id,'typhoon_review');
END;
$$;

CREATE FUNCTION public.cs_reapply(p_cancelled_booking_id uuid,p_slot_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE b public.cs_bookings; s public.cs_slots; bid uuid;
BEGIN
 SELECT * INTO b FROM public.cs_bookings WHERE id=p_cancelled_booking_id FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR auth.uid() NOT IN (b.vendor_user_id,b.community_user_id) THEN RAISE EXCEPTION 'participant_required'; END IF;
 IF b.status<>'cancelled' THEN RAISE EXCEPTION 'cancel_first'; END IF;
 SELECT * INTO s FROM public.cs_slots WHERE id=p_slot_id FOR UPDATE;
 IF NOT FOUND OR s.starts_at<=clock_timestamp() THEN RAISE EXCEPTION 'future_slot_required'; END IF;
 IF auth.uid()=b.community_user_id AND s.community_user_id<>auth.uid() THEN RAISE EXCEPTION 'own_community_slot_required'; END IF;
 IF EXISTS(SELECT 1 FROM public.cs_bookings WHERE slot_id=s.id AND status IN ('pending','confirmed')) THEN RAISE EXCEPTION 'slot_unavailable'; END IF;
 INSERT INTO public.cs_bookings(slot_id,vendor_user_id,community_user_id,label,status,reapplied_from,requested_by)
 VALUES(s.id,b.vendor_user_id,s.community_user_id,b.label,'pending',b.id,auth.uid()) RETURNING id INTO bid;
 INSERT INTO public.cs_notifications(recipient_id,booking_id,kind) VALUES(CASE WHEN auth.uid()=b.vendor_user_id THEN s.community_user_id ELSE b.vendor_user_id END,bid,'reapplied');
 RETURN bid;
END;
$$;
CREATE FUNCTION public.cs_read_notification(p_id uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
 UPDATE public.cs_notifications SET read_at=coalesce(read_at,clock_timestamp()) WHERE id=p_id AND recipient_id=auth.uid();
$$;
-- No public mutations, role selection, threshold changes or booking imports from browser.
REVOKE ALL ON public.cs_admins,public.cs_policy,public.cs_slots,public.cs_bookings,public.cs_cancellations,public.cs_typhoon_reviews,public.cs_notifications FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.cs_admins,public.cs_policy,public.cs_slots,public.cs_bookings,public.cs_cancellations,public.cs_typhoon_reviews,public.cs_notifications TO authenticated;
REVOKE ALL ON FUNCTION public.cs_is_admin(),public.cs_cancel_booking(uuid,text,jsonb),public.cs_review_typhoon(uuid,boolean,text),public.cs_reapply(uuid,uuid),public.cs_read_notification(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.cs_is_admin(),public.cs_cancel_booking(uuid,text,jsonb),public.cs_review_typhoon(uuid,boolean,text),public.cs_reapply(uuid,uuid),public.cs_read_notification(uuid) TO authenticated;
COMMIT;
