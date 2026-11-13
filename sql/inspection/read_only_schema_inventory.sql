-- 唯讀 schema 盤點，適用 Supabase SQL Editor；整份只執行一個 SELECT。
-- 不讀取業務資料列、auth.users、金鑰、Vault、pg_stats、cron 工作內容。
-- 不輸出欄位預設值、觸發器參數或函式本文。
-- 條件/索引/view 定義中的字串及數字常數會遮蔽；輸出不是可執行 DDL。
-- 目前盤點 public；如 discovered_schemas 顯示另有應用 schema，確認名稱後
-- 將其加入 scope 的 ARRAY，再執行此同一份 SELECT。不要加入 auth/storage/vault。
WITH
scope AS (SELECT ARRAY['public']::text[] AS schemas),
relations AS (
 SELECT c.oid,c.relname,c.relkind,c.relrowsecurity,c.relforcerowsecurity,c.relacl,c.relowner,n.nspname
 FROM pg_catalog.pg_class c
 JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 CROSS JOIN scope s
 WHERE n.nspname=ANY(s.schemas) AND c.relkind IN ('r','p','v','m','f')
),
routines AS (
 SELECT p.oid,p.proname,p.prokind,p.prosecdef,p.provolatile,p.proacl,p.proowner,p.proconfig,
 n.nspname,l.lanname
 FROM pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 JOIN pg_catalog.pg_language l ON l.oid=p.prolang
 CROSS JOIN scope s
 WHERE n.nspname=ANY(s.schemas)
),
fragments AS (
 SELECT 'constraint'::text AS kind,con.oid::text AS object_id,
 pg_catalog.pg_get_constraintdef(con.oid,true) AS definition
 FROM pg_catalog.pg_constraint con JOIN relations r ON r.oid=con.conrelid
 UNION ALL
 SELECT 'domain_constraint',con.oid::text,pg_catalog.pg_get_constraintdef(con.oid,true)
 FROM pg_catalog.pg_constraint con
 JOIN pg_catalog.pg_type t ON t.oid=con.contypid
 JOIN pg_catalog.pg_namespace n ON n.oid=t.typnamespace
 CROSS JOIN scope s WHERE n.nspname=ANY(s.schemas)
 UNION ALL
 SELECT 'index',i.indexrelid::text,pg_catalog.pg_get_indexdef(i.indexrelid)
 FROM pg_catalog.pg_index i JOIN relations r ON r.oid=i.indrelid
 UNION ALL
 SELECT 'policy_using',p.oid::text,pg_catalog.pg_get_expr(p.polqual,p.polrelid)
 FROM pg_catalog.pg_policy p JOIN relations r ON r.oid=p.polrelid
 UNION ALL
 SELECT 'policy_check',p.oid::text,pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)
 FROM pg_catalog.pg_policy p JOIN relations r ON r.oid=p.polrelid
 UNION ALL
 SELECT 'view',r.oid::text,pg_catalog.pg_get_viewdef(r.oid,true)
 FROM relations r WHERE r.relkind IN ('v','m')
),
redacted AS (
 SELECT kind,object_id,
 regexp_replace(
   regexp_replace(definition,$pattern$(?:[eE]'(?:[^'\\]|\\.|'')*'|'(?:[^']|'')*')$pattern$,$mask$'<literal-redacted>'$mask$,'g'),
   $pattern$\m[0-9]+(?:\.[0-9]+)?\M$pattern$,'<number-redacted>','g'
 ) AS definition
 FROM fragments
)
SELECT jsonb_build_object(
 'scope',(SELECT to_jsonb(s.schemas) FROM scope s),
 'notes',jsonb_build_array(
  'metadata_only_no_application_rows',
  'constants_redacted_not_executable_ddl',
  'function_bodies_defaults_trigger_arguments_omitted',
  'pg_depend_is_incomplete_for_dynamic_sql_and_plpgsql',
  'catalog_acl_is_not_a_proof_of_effective_end_to_end_authorization'
 ),
 'discovered_schemas',COALESCE((
  SELECT jsonb_agg(nspname ORDER BY nspname) FROM pg_catalog.pg_namespace
  WHERE nspname !~ '^pg_' AND nspname <> 'information_schema'
 ),'[]'::jsonb),
 'relations',COALESCE((
  SELECT jsonb_agg(jsonb_build_object(
   'schema',r.nspname,'name',r.relname,'kind',r.relkind,
   'rls_enabled',r.relrowsecurity,'rls_forced',r.relforcerowsecurity
  ) ORDER BY r.nspname,r.relname) FROM relations r
 ),'[]'::jsonb),
 'columns',COALESCE((
  SELECT jsonb_agg(jsonb_build_object(
   'schema',r.nspname,'table',r.relname,'position',a.attnum,'column',a.attname,
   'type',pg_catalog.format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,
   'has_default',a.atthasdef,'identity',a.attidentity,'generated',a.attgenerated
  ) ORDER BY r.nspname,r.relname,a.attnum)
  FROM relations r JOIN pg_catalog.pg_attribute a ON a.attrelid=r.oid
  WHERE a.attnum>0 AND NOT a.attisdropped
 ),'[]'::jsonb),
 'constraints',COALESCE((
  SELECT jsonb_agg(jsonb_build_object(
   'schema',r.nspname,'table',r.relname,'name',con.conname,'kind',con.contype,
   'validated',con.convalidated,'deferrable',con.condeferrable,'initially_deferred',con.condeferred,
   'columns',(SELECT jsonb_agg(a.attname ORDER BY k.ord) FROM unnest(con.conkey) WITH ORDINALITY k(num,ord) JOIN pg_catalog.pg_attribute a ON a.attrelid=r.oid AND a.attnum=k.num),
   'referenced_schema',rn.nspname,'referenced_table',rc.relname,
   'referenced_columns',(SELECT jsonb_agg(a.attname ORDER BY k.ord) FROM unnest(con.confkey) WITH ORDINALITY k(num,ord) JOIN pg_catalog.pg_attribute a ON a.attrelid=con.confrelid AND a.attnum=k.num),
   'on_update_code',con.confupdtype,'on_delete_code',con.confdeltype,
   'definition_redacted',d.definition
  ) ORDER BY r.nspname,r.relname,con.conname)
  FROM pg_catalog.pg_constraint con JOIN relations r ON r.oid=con.conrelid
  LEFT JOIN pg_catalog.pg_class rc ON rc.oid=con.confrelid
  LEFT JOIN pg_catalog.pg_namespace rn ON rn.oid=rc.relnamespace
  LEFT JOIN redacted d ON d.kind='constraint' AND d.object_id=con.oid::text
 ),'[]'::jsonb),
 'domain_types',COALESCE((
  SELECT jsonb_agg(jsonb_build_object(
   'schema',n.nspname,'type',t.typname,'base_type',pg_catalog.format_type(t.typbasetype,t.typtypmod),
   'not_null',t.typnotnull,'has_default',t.typdefaultbin IS NOT NULL,
   'constraints',(SELECT jsonb_agg(jsonb_build_object('name',c.conname,'definition_redacted',d.definition))
     FROM pg_catalog.pg_constraint c JOIN redacted d ON d.kind='domain_constraint' AND d.object_id=c.oid::text WHERE c.contypid=t.oid)
  ) ORDER BY n.nspname,t.typname)
  FROM pg_catalog.pg_type t JOIN pg_catalog.pg_namespace n ON n.oid=t.typnamespace
  CROSS JOIN scope s WHERE n.nspname=ANY(s.schemas) AND t.typtype='d'
 ),'[]'::jsonb),
 'enum_types',COALESCE((
  SELECT jsonb_agg(jsonb_build_object('schema',n.nspname,'type',t.typname,'label',e.enumlabel,'sort_order',e.enumsortorder) ORDER BY n.nspname,t.typname,e.enumsortorder)
  FROM pg_catalog.pg_type t JOIN pg_catalog.pg_namespace n ON n.oid=t.typnamespace
  JOIN pg_catalog.pg_enum e ON e.enumtypid=t.oid CROSS JOIN scope s WHERE n.nspname=ANY(s.schemas)
 ),'[]'::jsonb),
 'indexes',COALESCE((
  SELECT jsonb_agg(jsonb_build_object(
   'schema',r.nspname,'table',r.relname,'index',ic.relname,'unique',i.indisunique,
   'primary',i.indisprimary,'valid',i.indisvalid,'ready',i.indisready,
   'partial',i.indpred IS NOT NULL,'definition_redacted',d.definition
  ) ORDER BY r.nspname,r.relname,ic.relname)
  FROM pg_catalog.pg_index i JOIN relations r ON r.oid=i.indrelid
  JOIN pg_catalog.pg_class ic ON ic.oid=i.indexrelid
  LEFT JOIN redacted d ON d.kind='index' AND d.object_id=i.indexrelid::text
 ),'[]'::jsonb),
 'rls_policies',COALESCE((
  SELECT jsonb_agg(jsonb_build_object(
   'schema',r.nspname,'table',r.relname,'name',p.polname,'command_code',p.polcmd,
   'permissive',p.polpermissive,
   'roles',(SELECT jsonb_agg(CASE WHEN role_oid=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(role_oid)::text END) FROM unnest(p.polroles) role_oid),
   'using_redacted',u.definition,'with_check_redacted',w.definition
  ) ORDER BY r.nspname,r.relname,p.polname)
  FROM pg_catalog.pg_policy p JOIN relations r ON r.oid=p.polrelid
  LEFT JOIN redacted u ON u.kind='policy_using' AND u.object_id=p.oid::text
  LEFT JOIN redacted w ON w.kind='policy_check' AND w.object_id=p.oid::text
 ),'[]'::jsonb),
 'triggers',COALESCE((
  SELECT jsonb_agg(jsonb_build_object(
   'schema',r.nspname,'table',r.relname,'name',t.tgname,'enabled_code',t.tgenabled,
   'type_bitmask',t.tgtype,'function_schema',pn.nspname,'function',p.proname,
   'function_identity_arguments',pg_catalog.pg_get_function_identity_arguments(p.oid),
   'arguments_omitted',true,'when_expression_present',t.tgqual IS NOT NULL
  ) ORDER BY r.nspname,r.relname,t.tgname)
  FROM pg_catalog.pg_trigger t JOIN relations r ON r.oid=t.tgrelid
  JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
  JOIN pg_catalog.pg_namespace pn ON pn.oid=p.pronamespace
  WHERE NOT t.tgisinternal
 ),'[]'::jsonb),
 'routines',COALESCE((
  SELECT jsonb_agg(jsonb_build_object(
   'schema',p.nspname,'name',p.proname,'kind',p.prokind,'language',p.lanname,
   'identity_arguments',pg_catalog.pg_get_function_identity_arguments(p.oid),
   'result_type',pg_catalog.pg_get_function_result(p.oid),'security_definer',p.prosecdef,
   'volatility',p.provolatile,
   'search_path_setting_present',EXISTS(SELECT 1 FROM unnest(p.proconfig) v WHERE v LIKE 'search_path=%'),
   'body_omitted',true
  ) ORDER BY p.nspname,p.proname,p.oid) FROM routines p
 ),'[]'::jsonb),
 'table_grants',COALESCE((
  SELECT jsonb_agg(jsonb_build_object(
   'schema',r.nspname,'table',r.relname,
   'grantee',CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(x.grantee)::text END,
   'privilege',x.privilege_type,'grantable',x.is_grantable
  ) ORDER BY r.nspname,r.relname,x.grantee,x.privilege_type)
  FROM relations r CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(r.relacl,pg_catalog.acldefault('r',r.relowner))) x
 ),'[]'::jsonb),
 'column_grants',COALESCE((
  SELECT jsonb_agg(jsonb_build_object(
   'schema',r.nspname,'table',r.relname,'column',a.attname,
   'grantee',CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(x.grantee)::text END,'privilege',x.privilege_type
  ) ORDER BY r.nspname,r.relname,a.attnum,x.grantee,x.privilege_type)
  FROM relations r JOIN pg_catalog.pg_attribute a ON a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped
  CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) x
 ),'[]'::jsonb),
 'routine_grants',COALESCE((
  SELECT jsonb_agg(jsonb_build_object(
   'schema',p.nspname,'function',p.proname,'identity_arguments',pg_catalog.pg_get_function_identity_arguments(p.oid),
   'grantee',CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(x.grantee)::text END,'privilege',x.privilege_type
  ) ORDER BY p.nspname,p.proname,p.oid,x.grantee)
  FROM routines p CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) x
 ),'[]'::jsonb),
 'views_redacted',COALESCE((
  SELECT jsonb_agg(jsonb_build_object('schema',r.nspname,'name',r.relname,'definition_redacted',d.definition) ORDER BY r.nspname,r.relname)
  FROM relations r JOIN redacted d ON d.kind='view' AND d.object_id=r.oid::text
 ),'[]'::jsonb)
) AS schema_inventory;
