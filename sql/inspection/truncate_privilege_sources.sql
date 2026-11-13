-- READ ONLY. Metadata only: no table rows, credentials, auth.users or application RPCs.
-- PostgreSQL 17: traces direct/PUBLIC ACL, role inheritance, ownership and default ACL.
WITH RECURSIVE
clients AS (SELECT oid,rolname,rolsuper,rolbypassrls FROM pg_catalog.pg_roles WHERE rolname IN ('anon','authenticated')),
target AS (SELECT c.oid,c.relowner,c.relacl FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='bookings'),
paths AS (
 SELECT c.oid AS client,c.oid AS reached,ARRAY[c.oid] AS path,NULL::boolean AS inherit_option,NULL::boolean AS set_option FROM clients c
 UNION ALL
 SELECT p.client,m.roleid,p.path||m.roleid,m.inherit_option,m.set_option FROM paths p JOIN pg_catalog.pg_auth_members m ON m.member=p.reached WHERE NOT m.roleid=ANY(p.path)
),
acl AS (SELECT a.* FROM target t CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(t.relacl,pg_catalog.acldefault('r',t.relowner))) a WHERE a.privilege_type='TRUNCATE')
SELECT jsonb_build_object(
 'effective',COALESCE((SELECT jsonb_agg(jsonb_build_object('role',c.rolname,'superuser',c.rolsuper,'bypass_rls',c.rolbypassrls,'can_truncate',pg_catalog.has_table_privilege(c.oid,t.oid,'TRUNCATE'),'owner',pg_catalog.pg_get_userbyid(t.relowner),'inherits_owner',pg_catalog.pg_has_role(c.oid,t.relowner,'USAGE'))) FROM clients c CROSS JOIN target t),'[]'::jsonb),
 'truncate_acl_sources',COALESCE((SELECT jsonb_agg(jsonb_build_object('client',c.rolname,'grantor',pg_catalog.pg_get_userbyid(a.grantor),'grantee',CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(a.grantee)::text END,'grantable',a.is_grantable,'effective_without_set_role',CASE WHEN a.grantee=0 THEN true ELSE pg_catalog.pg_has_role(c.oid,a.grantee,'USAGE') END,'source_kind',CASE WHEN a.grantee=0 THEN 'PUBLIC' WHEN a.grantee=c.oid THEN 'direct' ELSE 'other_or_inherited_role' END)) FROM clients c CROSS JOIN acl a),'[]'::jsonb),
 'membership_paths',COALESCE((SELECT jsonb_agg(jsonb_build_object('client',pg_catalog.pg_get_userbyid(p.client),'path',(SELECT jsonb_agg(pg_catalog.pg_get_userbyid(x.role_oid) ORDER BY x.ord) FROM unnest(p.path) WITH ORDINALITY x(role_oid,ord)),'inherit_option',p.inherit_option,'set_option',p.set_option,'effective_without_set_role',pg_catalog.pg_has_role(p.client,p.reached,'USAGE'))) FROM paths p WHERE cardinality(p.path)>1),'[]'::jsonb),
 'truncate_default_acl',COALESCE((SELECT jsonb_agg(jsonb_build_object('creator',pg_catalog.pg_get_userbyid(d.defaclrole),'schema',CASE WHEN d.defaclnamespace=0 THEN '<global>' ELSE n.nspname END,'grantee',CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(a.grantee)::text END,'privilege',a.privilege_type)) FROM pg_catalog.pg_default_acl d LEFT JOIN pg_catalog.pg_namespace n ON n.oid=d.defaclnamespace CROSS JOIN LATERAL pg_catalog.aclexplode(d.defaclacl) a WHERE d.defaclobjtype='r' AND (d.defaclnamespace=0 OR n.nspname='public') AND a.privilege_type='TRUNCATE'),'[]'::jsonb)
) AS truncate_privilege_sources;
