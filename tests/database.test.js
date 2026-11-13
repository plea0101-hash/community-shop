import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
const V='00000000-0000-0000-0000-000000000001',C='00000000-0000-0000-0000-000000000002',A='00000000-0000-0000-0000-000000000003',X='00000000-0000-0000-0000-000000000004';
const db=new PGlite();
await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY); CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$; GRANT USAGE ON SCHEMA auth TO authenticated; INSERT INTO auth.users VALUES('${V}'),('${C}'),('${A}'),('${X}');`);
await db.exec(await readFile(new URL('../sql/drafts/20261113_cancellation.sql',import.meta.url),'utf8'));
await db.query('INSERT INTO public.cs_admins VALUES ($1)',[A]);
async function as(id){await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('SET ROLE authenticated');}
async function owner(){await db.exec('RESET ROLE');}
async function seed(hours=12){await owner();const s=(await db.query("INSERT INTO cs_slots(venue_ref,community_user_id,starts_at,ends_at) VALUES(gen_random_uuid()::text,$1,clock_timestamp()+($2||' hours')::interval,clock_timestamp()+(($2::numeric+3)||' hours')::interval) RETURNING *",[C,String(hours)])).rows[0];const b=(await db.query("INSERT INTO cs_bookings(slot_id,vendor_user_id,community_user_id,label,status) VALUES($1,$2,$3,'合成測試預約','confirmed') RETURNING *",[s.id,V,C])).rows[0];return {s,b};}
async function cancel(id,reason='合成取消原因',evidence=null){return(await db.query('SELECT cs_cancel_booking($1,$2,$3) AS id',[id,reason,evidence])).rows[0].id;}
async function row(table,id){return(await db.query(`SELECT * FROM ${table} WHERE id=$1`,[id])).rows[0];}
test('vendor cancellation is atomic, immutable, idempotent; slot can be re-applied as a new pending booking',async()=>{
 const {s,b}=await seed();await as(V);const id=await cancel(b.id);const c=await row('cs_cancellations',id);
 assert.equal(c.actor_id,V);assert.equal(c.actor_side,'vendor');assert.equal(c.timing,'late');assert.equal(c.late_hours_snapshot,'24');assert.equal(c.status,'cancelled');assert.equal(new Date(c.original_starts_at).toISOString(),new Date(s.starts_at).toISOString());
 assert.equal((await row('cs_bookings',b.id)).status,'cancelled');assert.equal(await cancel(b.id),id);
 await assert.rejects(db.query("UPDATE cs_cancellations SET reason='tampered' WHERE id=$1",[id]),/permission denied/);
 await as(C);const notices=(await db.query("SELECT * FROM cs_notifications WHERE booking_id=$1",[b.id])).rows;
 assert.equal(notices.length,1);assert.equal(notices[0].kind,'cancelled');
 await db.query('SELECT cs_read_notification($1)',[notices[0].id]);assert.ok((await row('cs_notifications',notices[0].id)).read_at);
 await as(V);const next=(await db.query('SELECT cs_reapply($1,$2) AS id',[b.id,s.id])).rows[0].id;
 assert.notEqual(next,b.id);assert.equal((await row('cs_bookings',next)).status,'pending');assert.equal((await row('cs_bookings',next)).reapplied_from,b.id);
 await assert.rejects(db.query('SELECT cs_reapply($1,$2)',[b.id,s.id]),/slot_unavailable/);
});
test('community can cancel; outsiders and admins cannot cancel someone else; RLS and direct DML denied',async()=>{
 const {b}=await seed(48);await as(X);
 assert.equal((await db.query('SELECT * FROM cs_bookings WHERE id=$1',[b.id])).rows.length,0);
 await assert.rejects(cancel(b.id),/booking_not_accessible/);
 await assert.rejects(db.query("UPDATE cs_bookings SET status='cancelled' WHERE id=$1",[b.id]),/permission denied/);
 await as(A);await assert.rejects(cancel(b.id),/booking_not_accessible/);
 await as(C);const id=await cancel(b.id,'');const c=await row('cs_cancellations',id);assert.equal(c.actor_side,'community');assert.equal(c.timing,'general');
 await as(X);assert.equal((await db.query('SELECT * FROM cs_cancellations WHERE id=$1',[id])).rows.length,0);
 await as(V);assert.equal((await db.query('SELECT * FROM cs_notifications WHERE booking_id=$1',[b.id])).rows.length,1);
});
test('late reason mandatory; started booking rejected; unknown policy never invents a classification',async()=>{
 const {b}=await seed();await as(V);await assert.rejects(cancel(b.id,'   '),/reason_required/);
 assert.equal((await row('cs_bookings',b.id)).status,'confirmed');
 const past=await seed(-5);await as(V);await assert.rejects(cancel(past.b.id),/activity_already_started/);
 await owner();await db.exec('UPDATE cs_policy SET late_hours=NULL');const unknown=await seed(1);await as(V);
 await assert.rejects(cancel(unknown.b.id,''),/reason_required/);
 const id=await cancel(unknown.b.id);assert.equal((await row('cs_cancellations',id)).timing,'unclassified');
 await owner();await db.exec('UPDATE cs_policy SET late_hours=24');
});
test('national school closure claim pending until independent admin review; audit and both notifications retained',async()=>{
 const {b,s}=await seed(12);await as(V);
 const taipei=d=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Taipei',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(d));
 const evidence={source_url:'https://www.dgpa.gov.tw/test-only',announced_on:taipei(new Date()),applicable_on:taipei(s.starts_at),county:'金門縣',suspension:'school'};
 await assert.rejects(cancel(b.id,'颱風測試',{...evidence,source_url:'https://gov.tw.attacker.invalid/'}),/invalid_typhoon_evidence/);
 await assert.rejects(cancel(b.id,'颱風測試',{...evidence,applicable_on:'1999-01-01'}),/invalid_typhoon_evidence/);
 const id=await cancel(b.id,'颱風測試',evidence);assert.equal((await row('cs_cancellations',id)).typhoon_status,'pending');
 await assert.rejects(db.query('SELECT cs_review_typhoon($1,true,$2)',[id,'fake']),/admin_required/);
 await owner();await db.query('INSERT INTO cs_admins VALUES($1)',[V]);await as(V);
 await assert.rejects(db.query('SELECT cs_review_typhoon($1,true,$2)',[id,'self review']),/independent_reviewer_required/);
 await owner();await db.query('DELETE FROM cs_admins WHERE user_id=$1',[V]);
 await as(A);await db.query('SELECT cs_review_typhoon($1,NULL,$2)',[id,'合成公告暫無法驗證，保留待審核']);
 assert.equal((await row('cs_cancellations',id)).typhoon_status,'pending');
 await db.query('SELECT cs_review_typhoon($1,true,$2)',[id,'僅合成測試，不是真實公告']);
 assert.equal((await row('cs_cancellations',id)).typhoon_status,'verified');
 assert.equal((await db.query('SELECT * FROM cs_typhoon_reviews WHERE cancellation_id=$1',[id])).rows.length,2);
 await assert.rejects(db.query('SELECT cs_review_typhoon($1,false,$2)',[id,'repeat']),/not_pending_review/);
 await as(C);assert.equal((await db.query("SELECT * FROM cs_notifications WHERE cancellation_id=$1 AND kind='typhoon_review'",[id])).rows.length,2);
 await as(V);assert.equal((await db.query("SELECT * FROM cs_notifications WHERE cancellation_id=$1 AND kind='typhoon_review'",[id])).rows.length,2);
});
test('anon cannot read private data or invoke cancellation RPC',async()=>{
 await owner();await db.exec('SET ROLE anon');
 await assert.rejects(db.query('SELECT * FROM cs_bookings'),/permission denied/);
 await assert.rejects(db.query('SELECT cs_cancel_booking($1,$2,NULL)',[V,'fake']),/permission denied/);
 await owner();
});

test('community reapplication is a new request restricted to its own slots; not a reschedule',async()=>{
 const {b,s}=await seed(48);await as(C);await cancel(b.id,'社區合成取消');
 const newId=(await db.query('SELECT cs_reapply($1,$2) AS id',[b.id,s.id])).rows[0].id;
 const request=await row('cs_bookings',newId);assert.equal(request.requested_by,C);assert.equal(request.status,'pending');
 assert.equal((await row('cs_bookings',b.id)).status,'cancelled');
 await as(V);assert.equal((await db.query("SELECT * FROM cs_notifications WHERE booking_id=$1 AND kind='reapplied'",[newId])).rows.length,1);
 await owner();const external=(await db.query("INSERT INTO cs_slots(venue_ref,community_user_id,starts_at,ends_at) VALUES('external',$1,now()+interval '5 days',now()+interval '5 days 3 hours') RETURNING id",[X])).rows[0].id;
 await as(C);await assert.rejects(db.query('SELECT cs_reapply($1,$2)',[b.id,external]),/own_community_slot_required/);
});

test('rejected official claim restores original late timing; cannot cancel other bookings automatically',async()=>{
 const {b,s}=await seed();const untouched=await seed();await as(V);
 const localDate=d=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Taipei',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(d));
 const id=await cancel(b.id,'合成查核不通過',{source_url:'https://www.dgpa.gov.tw/test-only',announced_on:localDate(new Date()),applicable_on:localDate(s.starts_at),county:'臺東縣',suspension:'work'});
 await as(A);await assert.rejects(db.query('SELECT cs_review_typhoon($1,false,$2)',[id,'   ']),/review_note_required/);
 await db.query('SELECT cs_review_typhoon($1,false,$2)',[id,'已確認不是颱風停班公告（合成測試）']);
 const record=await row('cs_cancellations',id);assert.equal(record.typhoon_status,'rejected');assert.equal(record.timing,'late');
 assert.equal((await row('cs_bookings',untouched.b.id)).status,'confirmed');
});

test('unique slot index rejects competing live bookings even outside the RPC',async()=>{
 const {b,s}=await seed();await owner();
 await assert.rejects(db.query("INSERT INTO cs_bookings(slot_id,vendor_user_id,community_user_id,label,status) VALUES($1,$2,$3,'competing synthetic booking','pending')",[s.id,X,C]),/cs_one_live_booking_per_slot/);
 await as(V);await cancel(b.id);
 await owner();await db.query("INSERT INTO cs_bookings(slot_id,vendor_user_id,community_user_id,label,status) VALUES($1,$2,$3,'released synthetic slot','confirmed')",[s.id,X,C]);
});
test.after(async()=>db.close());
