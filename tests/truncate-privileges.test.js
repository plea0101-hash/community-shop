import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {btree_gist} from '@electric-sql/pglite/contrib/btree_gist';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
const fixture=await read('./fixtures/production-booking.sql');
const aclFixture=await read('./fixtures/truncate-acl.sql');
const inspection=await read('../sql/inspection/truncate_privilege_sources.sql');
const verification=await read('../sql/inspection/truncate_fix_verification.sql');
const minimum=await read('../sql/drafts/20261113_truncate_minimum.sql');
const defaults=await read('../sql/drafts/20261113_truncate_default_acl.sql');
const undoTable=await read('../sql/rollback/20261113_restore_bookings_truncate.sql');
const undoDefaults=await read('../sql/rollback/20261113_restore_default_truncate.sql');
async function fresh(){const db=new PGlite({extensions:{btree_gist}});await db.exec(fixture+aclFixture);return db;}
async function report(db,sql=verification){await db.exec('BEGIN READ ONLY');try{return Object.values((await db.query(sql)).rows[0])[0];}finally{await db.exec('ROLLBACK');}}
const maintenance=s=>s.effective_permissions.filter(p=>['postgres','service_role'].includes(p.role));
const nonTargetTable=s=>s.bookings_acl.filter(a=>!(a.privilege==='TRUNCATE'&&['anon','authenticated'].includes(a.grantee)));
const nonTargetDefaults=s=>s.default_acl.filter(a=>!(a.schema==='public'&&a.privilege==='TRUNCATE'&&['anon','authenticated'].includes(a.grantee)));
const privileges=async(db,table)=>(await db.query(`SELECT r.rolname,p,has_table_privilege(r.oid,$1,p) AS allowed FROM pg_roles r CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) p WHERE r.rolname IN ('anon','authenticated','service_role','postgres','supabase_admin') ORDER BY r.rolname,p`,[table])).rows;

test('confirmed direct postgres grants: bookings-only fix preserves all non-target and maintenance ACL and data',async()=>{
 const db=await fresh();try{
  await db.exec("INSERT INTO bookings(venue_id,brand_id,start_time,end_time) VALUES(1,1,'2036-08-01T09:00Z','2036-08-01T12:00Z')");
  // Local rollback demonstration only: RLS does not protect TRUNCATE.
  await db.exec('BEGIN; SET LOCAL ROLE anon; TRUNCATE bookings; ROLLBACK');
  const source=await report(db,inspection);assert.equal(source.membership_paths.length,0);
  assert.ok(source.truncate_acl_sources.some(a=>a.source_kind==='direct'&&a.grantor==='postgres'));
  const before=await report(db);await db.exec(minimum);await db.exec(minimum);const after=await report(db);
  assert.equal(after.checks.bookings_clients_cannot_truncate,true);
  assert.equal(after.checks.future_public_client_truncate_sources_absent,false);
  assert.deepEqual(maintenance(after),maintenance(before));assert.deepEqual(nonTargetTable(after),nonTargetTable(before));assert.deepEqual(after.default_acl,before.default_acl);
  assert.deepEqual(after.bookings_rls,before.bookings_rls);assert.equal(after.bookings_owner,'postgres');
  assert.equal((await db.query('SELECT count(*) AS n FROM bookings')).rows[0].n,1);
 }finally{await db.close();}
});
test('future defaults for BOTH creators: only client TRUNCATE removed, no retroactive or cross-schema effects',async()=>{
 const db=await fresh();try{
  await db.exec('CREATE SCHEMA unrelated; ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA unrelated GRANT TRUNCATE ON TABLES TO anon; CREATE TABLE prior_postgres(id int); SET ROLE supabase_admin; CREATE TABLE public.prior_admin(id int); RESET ROLE');
  const before=await report(db);const oldPg=await privileges(db,'prior_postgres'),oldAdmin=await privileges(db,'prior_admin');
  await db.exec(defaults);await db.exec(defaults);const after=await report(db);
  assert.equal(after.checks.future_public_client_truncate_sources_absent,true);assert.equal(after.checks.bookings_clients_cannot_truncate,false);
  assert.deepEqual(after.bookings_acl,before.bookings_acl);assert.deepEqual(nonTargetDefaults(after),nonTargetDefaults(before));assert.deepEqual(maintenance(after),maintenance(before));
  await db.exec('CREATE TABLE next_postgres(id int); SET ROLE supabase_admin; CREATE TABLE public.next_admin(id int); RESET ROLE; CREATE TABLE unrelated.sentinel(id int)');
  for(const [table,prior] of [['next_postgres',oldPg],['next_admin',oldAdmin]]){
   const next=await privileges(db,table);
   for(let i=0;i<next.length;i++)assert.equal(next[i].allowed,['anon','authenticated'].includes(next[i].rolname)&&next[i].p==='TRUNCATE'?false:prior[i].allowed);
  }
  assert.deepEqual(await privileges(db,'prior_postgres'),oldPg);assert.deepEqual(await privileges(db,'prior_admin'),oldAdmin);
  assert.equal((await db.query("SELECT has_table_privilege('anon','unrelated.sentinel','TRUNCATE') AS unchanged")).rows[0].unchanged,true);
 }finally{await db.close();}
});
test('unexpected PUBLIC or inherited table grants cause rollback without touching shared roles',async()=>{
 for(const extra of ['GRANT TRUNCATE ON bookings TO PUBLIC','CREATE ROLE shared_maintenance; GRANT TRUNCATE ON bookings TO shared_maintenance; GRANT shared_maintenance TO authenticated']){
  const db=await fresh();try{
   await db.exec(extra);const before=await report(db);
   await assert.rejects(db.exec(minimum),/truncate_source_unresolved_no_partial_fix/);await db.exec('ROLLBACK');assert.deepEqual(await report(db),before);
  }finally{await db.close();}
 }
});
test('global default grant cannot be hidden by public-schema revoke; both creators roll back atomically',async()=>{
 const db=await fresh();try{
  await db.exec('ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT TRUNCATE ON TABLES TO anon');const before=await report(db);
  await assert.rejects(db.exec(defaults),/default_acl_truncate_source_unresolved/);await db.exec('ROLLBACK');assert.deepEqual(await report(db),before);
 }finally{await db.close();}
});
test('operator lacking supabase_admin authority gets no half-applied default fix',async()=>{
 const db=await fresh();try{
  const before=await report(db);await db.exec('CREATE ROLE limited_acl_operator; GRANT postgres TO limited_acl_operator; SET ROLE limited_acl_operator');
  await assert.rejects(db.exec(defaults),e=>e.code==='42501');await db.exec('ROLLBACK; RESET ROLE');assert.deepEqual(await report(db),before);
 }finally{await db.close();}
});
test('baseline rollback restores exact reported no-grant-option ACL; intervening tables do not change retroactively',async()=>{
 const db=await fresh();try{
  const baseline=await report(db);await db.exec(minimum);await db.exec(defaults);await db.exec('CREATE TABLE during_fix(id int)');
  assert.equal((await db.query("SELECT has_table_privilege('anon','during_fix','TRUNCATE') AS allowed")).rows[0].allowed,false);
  await db.exec(undoDefaults);await db.exec(undoTable);assert.deepEqual(await report(db),baseline);
  assert.equal((await db.query("SELECT has_table_privilege('anon','during_fix','TRUNCATE') AS allowed")).rows[0].allowed,false);
  await db.exec('CREATE TABLE after_rollback(id int)');assert.equal((await db.query("SELECT has_table_privilege('anon','after_rollback','TRUNCATE') AS exposed")).rows[0].exposed,true);
 }finally{await db.close();}
});

test('saved read-only baseline generates exact rollback including grant options without guessing',async()=>{
 const db=await fresh();try{
  await db.exec('GRANT TRUNCATE ON bookings TO anon WITH GRANT OPTION; ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT TRUNCATE ON TABLES TO anon WITH GRANT OPTION');
  const baseline=await report(db);assert.ok(baseline.rollback_from_snapshot.bookings.some(x=>x.sql.includes('WITH GRANT OPTION')));assert.ok(baseline.rollback_from_snapshot.defaults.some(x=>x.sql.includes('WITH GRANT OPTION')));
  await db.exec(minimum);await db.exec(defaults);
  for(const r of baseline.rollback_from_snapshot.defaults)await db.exec(r.sql);
  for(const r of baseline.rollback_from_snapshot.bookings){assert.equal(r.run_as_grantor,'postgres');await db.exec(r.sql);}
  assert.deepEqual(await report(db),baseline);
 }finally{await db.close();}
});
