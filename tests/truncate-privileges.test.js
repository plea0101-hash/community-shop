import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {btree_gist} from '@electric-sql/pglite/contrib/btree_gist';
const fixture=await readFile(new URL('./fixtures/production-booking.sql',import.meta.url),'utf8');
const inspection=await readFile(new URL('../sql/inspection/truncate_privilege_sources.sql',import.meta.url),'utf8');
const minimum=await readFile(new URL('../sql/drafts/20261113_truncate_minimum.sql',import.meta.url),'utf8');
async function inspect(db){await db.exec('BEGIN READ ONLY');try{return(await db.query(inspection)).rows[0].truncate_privilege_sources;}finally{await db.exec('ROLLBACK');}}
test('direct and PUBLIC sources reported read-only; minimum patch preserves unrelated privileges',async()=>{
 const db=new PGlite({extensions:{btree_gist}});try{
  await db.exec(fixture);await db.exec("GRANT TRUNCATE ON bookings TO PUBLIC; GRANT REFERENCES ON bookings TO authenticated; INSERT INTO bookings(venue_id,brand_id,start_time,end_time) VALUES(1,1,'2036-08-01T09:00Z','2036-08-01T12:00Z')");
  await db.exec('BEGIN; SET LOCAL ROLE anon; TRUNCATE bookings; ROLLBACK');
  assert.equal((await db.query('SELECT count(*) AS n FROM bookings')).rows[0].n,1);
  const before=await inspect(db);assert.ok(before.truncate_acl_sources.some(s=>s.source_kind==='direct'&&s.effective_without_set_role));assert.ok(before.truncate_acl_sources.some(s=>s.source_kind==='PUBLIC'&&s.effective_without_set_role));
  await db.exec(minimum);const after=await inspect(db);assert.ok(after.effective.every(s=>!s.can_truncate));
  assert.equal((await db.query("SELECT has_table_privilege('authenticated','bookings','REFERENCES') AS retained,has_table_privilege('authenticated','bookings','SELECT') AS select_allowed")).rows[0].retained,true);
  assert.equal((await db.query("SELECT has_table_privilege('authenticated','bookings','SELECT') AS allowed")).rows[0].allowed,false);
 }finally{await db.close();}
});
test('inherited TRUNCATE survives direct revoke: report path and refuse a partial fix',async()=>{
 const db=new PGlite({extensions:{btree_gist}});try{
  await db.exec(fixture);await db.exec('CREATE ROLE booking_maintenance; GRANT TRUNCATE ON bookings TO booking_maintenance; GRANT booking_maintenance TO authenticated');
  const report=await inspect(db);assert.ok(report.truncate_acl_sources.some(s=>s.client==='authenticated'&&s.grantee==='booking_maintenance'&&s.effective_without_set_role));assert.ok(report.membership_paths.some(p=>p.path.includes('booking_maintenance')));
  await assert.rejects(db.exec(minimum),/truncate_source_unresolved_no_partial_fix/);await db.exec('ROLLBACK');
  assert.equal((await db.query("SELECT has_table_privilege('anon','bookings','TRUNCATE') AS unchanged")).rows[0].unchanged,true);
 }finally{await db.close();}
});
test('default ACL can recreate TRUNCATE exposure on future tables and is reported separately',async()=>{
 const db=new PGlite({extensions:{btree_gist}});try{
  await db.exec(fixture);await db.exec('ALTER DEFAULT PRIVILEGES GRANT TRUNCATE ON TABLES TO anon; ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT TRUNCATE ON TABLES TO authenticated');
  const report=await inspect(db);assert.ok(report.truncate_default_acl.some(a=>a.grantee==='anon'&&a.schema==='<global>'));assert.ok(report.truncate_default_acl.some(a=>a.grantee==='authenticated'&&a.schema==='public'));
  await db.exec(minimum);await db.exec('CREATE TABLE future_synthetic_table(id integer)');
  assert.equal((await db.query("SELECT has_table_privilege('anon','future_synthetic_table','TRUNCATE') AS risk")).rows[0].risk,true);
 }finally{await db.close();}
});
