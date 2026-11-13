import {test,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {btree_gist} from '@electric-sql/pglite/contrib/btree_gist';
const db=new PGlite({extensions:{btree_gist}});
const V='10000000-0000-0000-0000-000000000001',C='10000000-0000-0000-0000-000000000002',A='10000000-0000-0000-0000-000000000003',X='10000000-0000-0000-0000-000000000004';
// Confirmed production defaults, active states, [) and CHECK; membership/eligibility/payment approval remain local test fixtures.
const baseFixture=await readFile(new URL('./fixtures/production-booking.sql',import.meta.url),'utf8');
await db.exec(baseFixture);
await db.exec(await readFile(new URL('../sql/drafts/20261113_production_booking_rpcs.sql',import.meta.url),'utf8'));
await db.query('INSERT INTO booking_brand_members VALUES(1,$1,true)',[V]);
await db.query('INSERT INTO booking_community_members VALUES(1,$1,true)',[C]);
let sequence=0;
const key=()=>`20000000-0000-0000-0000-${String(++sequence).padStart(12,'0')}`;
async function as(id){await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('SET ROLE authenticated');}
async function owner(){await db.exec('RESET ROLE');}
async function config(){await owner();await db.exec("UPDATE booking_workflow_config SET active_states=ARRAY['pending','confirmed'],create_state='pending',cancelled_state='cancelled',brand_state='approved',venue_state='available',community_state='approved',membership_reviewed=true,payment_reviewed=true");}
const interval=(day=1)=>[`2035-08-${String(day).padStart(2,'0')}T09:00:00Z`,`2035-08-${String(day).padStart(2,'0')}T12:00:00Z`];
async function request(day=1,k=key(),venue=1){const [s,e]=interval(day);return(await db.query('SELECT booking_request($1,1,$2,$3,$4) AS id',[venue,s,e,k])).rows[0].id;}
async function cancel(id,reason='',evidence=null){return(await db.query('SELECT booking_cancel($1,$2,$3) AS id',[id,reason,evidence])).rows[0].id;}
async function booking(id){return(await db.query('SELECT * FROM bookings WHERE id=$1',[id])).rows[0];}
test('confirmed contract is seeded but membership and payment reviews remain closed',async()=>{
 await owner();const defaults=(await db.query('SELECT * FROM booking_workflow_config')).rows[0];
 assert.deepEqual(defaults.active_states,['pending','confirmed']);assert.equal(defaults.create_state,'pending');assert.equal(defaults.venue_state,'available');
 assert.equal(defaults.membership_reviewed,false);assert.equal(defaults.payment_reviewed,false);
 await as(V);await assert.rejects(request(),/production_contract_not_configured/);
 await config();await db.exec('UPDATE booking_workflow_config SET membership_reviewed=false,payment_reviewed=false');
 await as(V);await assert.rejects(request(),/membership_review_required/);
 await owner();await db.exec('UPDATE booking_workflow_config SET membership_reviewed=true');await as(V);await assert.rejects(request(),/payment_review_required/);
 await config();await db.exec("ALTER TABLE bookings DROP CONSTRAINT bookings_no_overlap; ALTER TABLE bookings ADD CONSTRAINT bookings_no_overlap EXCLUDE USING gist(venue_id WITH =,tstzrange(start_time,end_time,'[]') WITH &&) WHERE(status=ANY(ARRAY['pending'::text,'confirmed'::text]))");
 await as(V);await assert.rejects(request(),/production_overlap_contract_mismatch/);
 await owner();await db.exec("ALTER TABLE bookings DROP CONSTRAINT bookings_no_overlap; ALTER TABLE bookings ADD CONSTRAINT bookings_no_overlap EXCLUDE USING gist(venue_id WITH =,tstzrange(start_time,end_time,'[)') WITH &&) WHERE(status=ANY(ARRAY['pending'::text,'confirmed'::text]))");
});
test('request writes only public.bookings; request key replay checks payload; rejects direct writes and TRUNCATE',async()=>{
 await as(V);const k=key();const id=await request(1,k);assert.equal(await request(1,k),id);
 await owner();await db.exec("SET TIME ZONE 'Asia/Taipei'");await as(V);assert.equal(await request(1,k),id);
 await assert.rejects(request(2,k),/request_key_payload_mismatch/);
 assert.equal((await booking(id)).status,'pending');
 await assert.rejects(db.exec('TRUNCATE bookings'),/permission denied/);
 await assert.rejects(db.query("UPDATE bookings SET status='confirmed' WHERE id=$1",[id]),/permission denied/);
 await assert.rejects(db.query('SELECT booking_submit_internal(1,1,$1,$2,$3,NULL)',[...interval(2),key()]),/permission denied/);
 await as(X);assert.equal((await db.query('SELECT * FROM bookings')).rows.length,0);await assert.rejects(request(2),/brand_membership_required/);
 await as(C);assert.ok(await booking(id));
});
test('real GiST overlap constraint rejects partial and enclosed overlaps, allows adjacent and other venues',async()=>{
 await as(V);await assert.rejects(request(1),/bookings_no_overlap/);
 for(const [s,e] of [['2035-08-01T08:00Z','2035-08-01T10:00Z'],['2035-08-01T10:00Z','2035-08-01T11:00Z'],['2035-08-01T08:00Z','2035-08-01T13:00Z']])await assert.rejects(db.query('SELECT booking_request(1,1,$1,$2,$3)',[s,e,key()]),/bookings_no_overlap/);
 const adjacent=(await db.query('SELECT booking_request(1,1,$1,$2,$3) AS id',['2035-08-01T12:00Z','2035-08-01T14:00Z',key()])).rows[0].id;
 assert.ok(adjacent);assert.ok(await request(1,key(),2));
 await assert.rejects(db.query('SELECT booking_request(1,1,$1,$2,$3)',['2035-08-02T12:00Z','2035-08-02T09:00Z',key()]),/invalid_future_interval/);
});
test('cancel releases original overlapping range; reapply makes a new booking and preserves audit; idempotent replay',async()=>{
 await as(V);const id=await request(3);const eid=await cancel(id);assert.equal(await cancel(id),eid);
 assert.equal((await booking(id)).status,'cancelled');const k=key();
 const next=(await db.query('SELECT booking_reapply($1,1,$2,$3,$4) AS id',[id,...interval(3),k])).rows[0].id;
 assert.notEqual(next,id);assert.equal((await booking(id)).status,'cancelled');assert.equal((await booking(next)).status,'pending');
 assert.equal((await db.query('SELECT booking_reapply($1,1,$2,$3,$4) AS id',[id,...interval(3),k])).rows[0].id,next);
 await assert.rejects(db.query('SELECT booking_reapply($1,1,$2,$3,$4)',[next,...interval(4),key()]),/cancel_first/);
 await as(C);assert.equal((await db.query("SELECT * FROM booking_event_notifications WHERE event_key=$1",['cancelled:'+eid])).rows.length,1);
});
test('community cancellation authorized, outsiders and administrator cannot impersonate parties',async()=>{
 await as(V);const id=await request(5);await as(X);await assert.rejects(cancel(id),/booking_not_accessible/);
 await as(A);await assert.rejects(cancel(id),/booking_not_accessible/);
 await as(C);const eid=await cancel(id,'合成社區取消');assert.equal((await db.query('SELECT actor_side FROM booking_cancellation_events WHERE id=$1',[eid])).rows[0].actor_side,'community');
 await as(X);assert.equal((await db.query('SELECT * FROM booking_cancellation_events')).rows.length,0);
});
test('server inclusive 24-hour precision; late reason mandatory and begun activities rejected',async()=>{
 await owner();
 assert.equal((await db.query("SELECT booking_timing('2035-08-01T12:00Z','2035-07-31T12:00Z') AS timing")).rows[0].timing,'late');
 assert.equal((await db.query("SELECT booking_timing('2035-08-01T12:00Z','2035-07-31T11:59:59.999999Z') AS timing")).rows[0].timing,'general');
 const id=(await db.query("INSERT INTO bookings(venue_id,brand_id,start_time,end_time,status) VALUES(1,1,clock_timestamp()+interval '12 hours',clock_timestamp()+interval '15 hours','confirmed') RETURNING id")).rows[0].id;
 await as(V);await assert.rejects(cancel(id),/valid_reason_required/);assert.equal((await booking(id)).status,'confirmed');await cancel(id,'合成臨時原因');
 await owner();const past=(await db.query("INSERT INTO bookings(venue_id,brand_id,start_time,end_time,status) VALUES(1,1,now()-interval '4 hours',now()-interval '1 hour','confirmed') RETURNING id")).rows[0].id;
 await as(V);await assert.rejects(cancel(past,'合成'),/activity_already_started/);
});
test('national typhoon claim remains pending until independent review; review does not revive inventory',async()=>{
 await as(V);const id=await request(6);
 const evidence={source_url:'https://www.dgpa.gov.tw/test-only',announced_on:'2026-01-01',applicable_on:'2035-08-06',county:'金門縣',suspension:'school'};
 const eid=await cancel(id,'合成颱風取消',evidence);
 await assert.rejects(db.query('SELECT booking_review_typhoon($1,$2,$3)',[eid,'verified','fake']),/admin_required/);
 await as(A);await db.query('SELECT booking_review_typhoon($1,$2,$3)',[eid,'pending','暫無法核驗（合成）']);
 await db.query('SELECT booking_review_typhoon($1,$2,$3)',[eid,'verified','已核驗（合成，非真實公告）']);
 const c=(await db.query('SELECT * FROM booking_cancellation_events WHERE id=$1',[eid])).rows[0];assert.equal(c.typhoon_status,'verified');
 assert.equal((await booking(id)).status,'cancelled');assert.equal((await db.query('SELECT * FROM booking_cancellation_reviews WHERE event_id=$1',[eid])).rows.length,2);
 await as(V);assert.ok(await request(6));
});


test('missing recipients retain durable organization outbox; transaction failure leaves no booking or notice',async()=>{
 await owner();await db.query('DELETE FROM booking_community_members WHERE user_id=$1',[C]);
 await as(V);const id=await request(7);await cancel(id);
 await owner();const rows=(await db.query('SELECT * FROM booking_event_outbox WHERE booking_id=$1',[id])).rows;
 assert.equal(rows.length,2);assert.ok(rows.every(r=>r.community_id===1 && r.delivery_state==='pending'));
 await db.query('INSERT INTO booking_community_members VALUES(1,$1,true)',[C]);
 const before=(await db.query('SELECT count(*) AS n FROM bookings')).rows[0].n;
 await as(V);await assert.rejects(request(1),/bookings_no_overlap/);
 await owner();assert.equal((await db.query('SELECT count(*) AS n FROM bookings')).rows[0].n,before);
});
test('verified and pending excluded from late count; rejected retains original timing; viewer RLS remains effective',async()=>{
 await owner();const id=(await db.query("INSERT INTO bookings(venue_id,brand_id,start_time,end_time,status) VALUES(2,1,clock_timestamp()+interval '10 hours',clock_timestamp()+interval '11 hours','confirmed') RETURNING id")).rows[0].id;
 const s=(await booking(id)).start_time;
 const date=d=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Taipei',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(d));
 await as(V);const eid=await cancel(id,'合成颱風原因',{source_url:'https://www.dgpa.gov.tw/test-only',announced_on:date(new Date()),applicable_on:date(s),county:'連江縣',suspension:'school'});
 assert.equal((await db.query('SELECT * FROM booking_cancellation_classification WHERE id=$1',[eid])).rows[0].counts_as_general_late,false);
 await as(A);await db.query('SELECT booking_review_typhoon($1,$2,$3)',[eid,'rejected','確認不符合（合成）']);
 assert.equal((await db.query('SELECT * FROM booking_cancellation_classification WHERE id=$1',[eid])).rows[0].counts_as_general_late,true);
 await as(X);assert.equal((await db.query('SELECT * FROM booking_cancellation_classification')).rows.length,0);
 await owner();await db.exec('SET ROLE anon');await assert.rejects(db.query('SELECT booking_request(1,1,$1,$2,$3)',[...interval(8),key()]),/permission denied/);
});


test('follow-up catalog query is read-only and reports the exact synthetic exclusion contract',async()=>{
 await owner();await db.exec('BEGIN READ ONLY');
 try {
  const sql=await readFile(new URL('../sql/inspection/booking_contract_details.sql',import.meta.url),'utf8');
  const out=(await db.query(sql)).rows[0].booking_contract_details;
  assert.ok(out.constraints.some(c=>c.name==='bookings_no_overlap'&&c.definition.includes('[)')));
  assert.equal(out.effective_booking_privileges.find(r=>r.role==='anon').truncate,false);
 } finally {await db.exec('ROLLBACK');}
});
test('inherited direct-write privilege blocks installation and rolls back the entire draft',async()=>{
 const isolated=new PGlite({extensions:{btree_gist}});
 try {
  await isolated.exec(baseFixture);
  await isolated.exec('CREATE ROLE inherited_writer; GRANT INSERT ON bookings TO inherited_writer; GRANT inherited_writer TO authenticated');
  const sql=await readFile(new URL('../sql/drafts/20261113_production_booking_rpcs.sql',import.meta.url),'utf8');
  await assert.rejects(isolated.exec(sql),/inherited_booking_write_privilege_remains/);
  await isolated.exec('ROLLBACK');
  assert.equal((await isolated.query("SELECT to_regclass('public.booking_workflow_config') AS object")).rows[0].object,null);
  assert.equal((await isolated.query("SELECT has_table_privilege('anon','public.bookings','TRUNCATE') AS original_privilege")).rows[0].original_privilege,true);
 } finally {await isolated.close();}
});


test('unreviewed membership or payment blocks request, cancellation and reapplication without side effects',async()=>{
 await config();await as(V);const live=await request(9);const old=await request(10);await cancel(old);
 for(const gate of ['payment','membership']) {
  await owner();await db.query('UPDATE booking_workflow_config SET membership_reviewed=$1,payment_reviewed=$2',[gate!=='membership',gate!=='payment']);
  await as(V);const expected=new RegExp(gate+'_review_required');
  await assert.rejects(request(11),expected);await assert.rejects(cancel(live),expected);
  await assert.rejects(db.query('SELECT booking_reapply($1,1,$2,$3,$4)',[old,...interval(11),key()]),expected);
  if(gate==='membership')assert.equal((await db.query('SELECT * FROM bookings')).rows.length,0);
  await owner();assert.equal((await booking(live)).status,'pending');
  assert.equal((await db.query('SELECT count(*) AS n FROM booking_cancellation_events WHERE booking_id=$1',[live])).rows[0].n,0);
 }
 await config();
});
test('duplicate cancellation preserves original actor/reason and does not release a replacement booking',async()=>{
 await as(V);const id=await request(12);const eid=await cancel(id,'original reason');const replacement=await request(12);
 await as(C);assert.equal(await cancel(id,'changed retry reason'),eid);
 assert.equal((await booking(replacement)).status,'pending');
 const audit=(await db.query('SELECT * FROM booking_cancellation_events WHERE id=$1',[eid])).rows[0];assert.equal(audit.actor_id,V);assert.equal(audit.reason,'original reason');
 assert.equal((await db.query('SELECT count(*) AS n FROM booking_cancellation_events WHERE booking_id=$1',[id])).rows[0].n,1);
});
test('failure after status update rolls back cancellation event, status, notification and outbox',async()=>{
 await as(V);const id=await request(13);await owner();
 // Inject a synthetic outbox failure after the function has updated bookings.
 await db.exec("CREATE FUNCTION synthetic_outbox_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.event_key LIKE 'cancelled:%' THEN RAISE EXCEPTION 'injected_outbox_failure'; END IF; RETURN NEW; END $$; CREATE TRIGGER synthetic_outbox_failure BEFORE INSERT ON booking_event_outbox FOR EACH ROW EXECUTE FUNCTION synthetic_outbox_failure()");
 await as(V);await assert.rejects(cancel(id),/injected_outbox_failure/);assert.equal((await booking(id)).status,'pending');
 await owner();assert.equal((await db.query('SELECT count(*) AS n FROM booking_cancellation_events WHERE booking_id=$1',[id])).rows[0].n,0);
 assert.equal((await db.query("SELECT count(*) AS n FROM booking_event_outbox WHERE booking_id=$1 AND event_key LIKE 'cancelled:%'",[id])).rows[0].n,0);
 assert.equal((await db.query("SELECT count(*) AS n FROM booking_event_notifications WHERE booking_id=$1 AND event_key LIKE 'cancelled:%'",[id])).rows[0].n,0);
 await db.exec('DROP TRIGGER synthetic_outbox_failure ON booking_event_outbox; DROP FUNCTION synthetic_outbox_failure()');
});


test('confirmed defaults and time CHECK detect drift; pending is not eligibility approval',async()=>{
 await config();await db.exec("ALTER TABLE venues ALTER COLUMN status SET DEFAULT 'unavailable'");
 await as(V);await assert.rejects(request(14),/production_status_default_mismatch/);
 await owner();await db.exec("ALTER TABLE venues ALTER COLUMN status SET DEFAULT 'available'; ALTER TABLE bookings DROP CONSTRAINT bookings_valid_time; ALTER TABLE bookings ADD CONSTRAINT bookings_valid_time CHECK(end_time>=start_time)");
 await as(V);await assert.rejects(request(14),/production_time_check_mismatch/);
 await owner();await db.exec("ALTER TABLE bookings DROP CONSTRAINT bookings_valid_time; ALTER TABLE bookings ADD CONSTRAINT bookings_valid_time CHECK(end_time>start_time); UPDATE brands SET status='pending' WHERE id=1");
 await as(V);await assert.rejects(request(14),/brand_not_eligible/);
 await owner();await db.exec("UPDATE brands SET status='approved' WHERE id=1; UPDATE communities SET status='pending' WHERE id=1");
 await as(V);await assert.rejects(request(14),/community_not_eligible/);
 await owner();await db.exec("UPDATE communities SET status='approved' WHERE id=1");
});
after(async()=>db.close());
