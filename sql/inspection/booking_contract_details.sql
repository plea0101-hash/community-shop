-- 單一唯讀 SELECT；不讀業務資料、Auth 使用者、金鑰或函式本文。
-- 只補上先前被遮蔽的時段邊界及業務狀態常數，回傳前請檢閱。
SELECT jsonb_build_object(
 'constraints',(
  SELECT jsonb_agg(jsonb_build_object('name',conname,'definition',pg_get_constraintdef(oid,true)))
  FROM pg_constraint WHERE conrelid='public.bookings'::regclass
  AND conname IN ('bookings_no_overlap','bookings_valid_time')
 ),
 'status_defaults',(
  SELECT jsonb_agg(jsonb_build_object('table',c.relname,'definition',pg_get_expr(d.adbin,d.adrelid)))
  FROM pg_attrdef d JOIN pg_class c ON c.oid=d.adrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=d.adnum
  WHERE n.nspname='public' AND c.relname IN ('bookings','brands','venues','communities') AND a.attname='status'
 ),
 'effective_booking_privileges',(
  SELECT jsonb_agg(jsonb_build_object('role',rolname,'superuser',rolsuper,'bypass_rls',rolbypassrls,
   'select',has_table_privilege(oid,'public.bookings','SELECT'),
   'insert',has_table_privilege(oid,'public.bookings','INSERT'),
   'update',has_table_privilege(oid,'public.bookings','UPDATE'),
   'truncate',has_table_privilege(oid,'public.bookings','TRUNCATE')))
  FROM pg_roles WHERE rolname IN ('anon','authenticated')
 )
) AS booking_contract_details;
