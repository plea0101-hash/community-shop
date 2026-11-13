"""Real multi-session PostgreSQL tests, synthetic data only, network-disabled container."""
from pathlib import Path
import os, subprocess, time, uuid, selectors, json

ROOT=Path(__file__).resolve().parents[1]
IMAGE='postgres@sha256:40865bc877a289da75963d97d72b59633f639fc5af7a4e856bfa3714cae5b536'
DOCKER=['docker','--host=unix:///var/run/docker.sock']
ENV=os.environ.copy()
for key in ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']:
    ENV.pop(key,None)
NAME='community-shop-rpc-test-'+uuid.uuid4().hex[:12]
V='10000000-0000-0000-0000-000000000001'
C='10000000-0000-0000-0000-000000000002'
created=False
sessions=[]

def docker(*args,**kwargs):
    return subprocess.run(DOCKER+list(args),env=ENV,text=True,capture_output=True,**kwargs)
def command():
    return DOCKER+['exec','-i',NAME,'psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres']
def query(sql,ok=True):
    r=subprocess.run(command(),input=sql,env=ENV,text=True,capture_output=True,timeout=15)
    if ok and r.returncode: raise AssertionError(r.stderr)
    return r

def actor_sql(actor=V,app='observer'):
    return f"SET application_name='{app}'; SET request.jwt.claim.sub='{actor}'; SET ROLE authenticated;"
def request_sql(day,key=None):
    key=key or str(uuid.uuid4())
    return f"SELECT booking_request(1,1,'2036-08-{day:02}T09:00Z','2036-08-{day:02}T12:00Z','{key}');"
def launch(sql):
    p=subprocess.Popen(command(),env=ENV,text=True,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    sessions.append(p);p.stdin.write(sql+'\n');p.stdin.flush();return p

def hold(sql,actor=V):
    p=launch(actor_sql(actor,'holder')+'BEGIN;'+sql+"SELECT 'READY';")
    ready=selectors.DefaultSelector();ready.register(p.stdout,selectors.EVENT_READ)
    lines=[];deadline=time.monotonic()+15
    # Read returned IDs through the readiness marker; lock checks, rather than sleeps, coordinate sessions.
    if not ready.select(15):raise AssertionError('holder did not become ready')
    while time.monotonic()<deadline:
        line=p.stdout.readline().strip();lines.append(line)
        if line=='READY':return p,lines
        if p.poll() is not None:raise AssertionError(p.stderr.read())
    raise AssertionError('holder readiness timeout')

def contender(sql,actor=V):
    p=launch(actor_sql(actor,'contender')+sql+'\n\\q')
    for _ in range(100):
        if query("SELECT count(*) FROM pg_stat_activity WHERE application_name='contender' AND cardinality(pg_blocking_pids(pid))>0;").stdout.strip()=='1':return p
        if p.poll() is not None:raise AssertionError('contender finished before lock contention: '+p.stderr.read())
        time.sleep(.03)
    raise AssertionError('did not observe a blocked second session')
def finish(p,commit=None):
    if commit is not None:p.stdin.write(commit+';\n\\q\n');p.stdin.flush()
    out,err=p.communicate(timeout=15)
    return p.returncode,out.strip(),err

def count(sql):return int(query(sql).stdout.strip())

try:
    r=docker('run','-d','--rm','--pull=never','--name',NAME,'--network','none','--memory','512m','--cpus','2',
             '--tmpfs','/var/lib/postgresql/data','-e','POSTGRES_HOST_AUTH_METHOD=trust',IMAGE,'-c','listen_addresses=')
    assert r.returncode==0,r.stderr
    created=True
    for _ in range(200):
        if docker('exec',NAME,'cat','/proc/1/comm').stdout.strip()=='postgres' and docker('exec',NAME,'pg_isready','-U','postgres').returncode==0:break
        time.sleep(.05)
    else:raise AssertionError('local PostgreSQL not ready')
    query((ROOT/'tests/fixtures/production-booking.sql').read_text())
    query((ROOT/'tests/fixtures/truncate-acl.sql').read_text())
    verification=(ROOT/'sql/inspection/truncate_fix_verification.sql').read_text()
    before=json.loads(query(verification).stdout)
    assert not before['checks']['bookings_clients_cannot_truncate']
    expected=json.loads((ROOT/'tests/fixtures/truncate-baseline.json').read_text())
    for field in ['bookings_acl','default_acl','effective_permissions']:
        canonical=lambda rows:sorted(json.dumps(r,sort_keys=True) for r in rows)
        assert canonical(before[field])==canonical(expected[field]),field
    assert before['checks']['service_role_bookings_dml_still_absent']
    authority=json.loads(query((ROOT/'sql/inspection/truncate_executor_preflight.sql').read_text()).stdout)
    assert authority['catalog_estimate_only'] and authority['managed_platform_authorization_still_required']
    query((ROOT/'sql/drafts/20261113_truncate_minimum.sql').read_text())
    query((ROOT/'sql/drafts/20261113_truncate_default_acl.sql').read_text())
    after=json.loads(query(verification).stdout)
    assert after['checks']['bookings_clients_cannot_truncate'] and after['checks']['future_public_client_truncate_sources_absent']
    maintenance=lambda d:[p for p in d['effective_permissions'] if p['role'] in ('postgres','service_role')]
    assert maintenance(after)==maintenance(before)
    assert after['checks']['service_role_bookings_dml_still_absent']
    query('CREATE TABLE acl_future_pg(id int); SET ROLE supabase_admin; CREATE TABLE public.acl_future_admin(id int); RESET ROLE;')
    for table in ['acl_future_pg','acl_future_admin']:
        for role in ['anon','authenticated']:
            assert query(f"SELECT has_table_privilege('{role}','{table}','TRUNCATE');").stdout.strip()=='f'
        assert query(f"SELECT has_table_privilege('service_role','{table}','TRUNCATE');").stdout.strip()=='t'
    print('PASS ACL preflight: exact supplied baseline, service DML remains false, executor check is metadata-only; both fixes preserve maintenance and future table protection',flush=True)
    for r in before['rollback_from_snapshot']['defaults']:
        query(r['sql'])
    for r in before['rollback_from_snapshot']['bookings']:
        assert r['run_as_grantor']=='postgres'
        query(r['sql'])
    assert json.loads(query(verification).stdout)==before
    for table in ['acl_future_pg','acl_future_admin']:
        assert query(f"SELECT has_table_privilege('anon','{table}','TRUNCATE');").stdout.strip()=='f'
    query((ROOT/'sql/drafts/20261113_truncate_minimum.sql').read_text())
    query((ROOT/'sql/drafts/20261113_truncate_default_acl.sql').read_text())
    print('PASS ACL rollback: saved baseline restored exactly; no retroactive grant to intervening tables; fixes re-applied locally',flush=True)
    query((ROOT/'sql/drafts/20261113_production_booking_rpcs.sql').read_text())
    query(f"INSERT INTO booking_brand_members VALUES(1,'{V}',true);INSERT INTO booking_community_members VALUES(1,'{C}',true);")
    denied=query(actor_sql()+request_sql(1),ok=False)
    assert denied.returncode and 'production_contract_not_configured' in denied.stderr
    # These are LOCAL test approvals only. Production remains unconfigured and disabled.
    query("UPDATE booking_workflow_config SET cancelled_state='cancelled',brand_state='approved',community_state='approved',membership_reviewed=true,payment_reviewed=true;")
    print('PASS setup: PostgreSQL '+query('SHOW server_version;').stdout.strip()+'; network=none, no published ports; unconfigured RPC denied',flush=True)

    a,_=hold(request_sql(1));b=contender(request_sql(1))
    assert finish(a,'COMMIT')[0]==0
    code,out,err=finish(b);assert code and 'bookings_no_overlap' in err,err
    assert count("SELECT count(*) FROM bookings WHERE start_time='2036-08-01T09:00Z';")==1
    print('PASS concurrent overlap: second session observed blocked; commit admits exactly one booking',flush=True)

    k=str(uuid.uuid4());sql=request_sql(2,k)
    a,first=hold(sql);b=contender(sql)
    assert finish(a,'COMMIT')[0]==0
    code,out,err=finish(b);assert code==0,err
    assert out==first[0],(out,first)
    assert count(f"SELECT count(*) FROM booking_request_keys WHERE request_key='{k}';")==1
    print('PASS same request key: concurrent retries return one booking ID',flush=True)

    bid=query(actor_sql()+request_sql(3)).stdout.strip()
    a,first=hold(f"SELECT booking_cancel({bid},'local synthetic cancel',NULL);")
    b=contender(f"SELECT booking_cancel({bid},'other party retry',NULL);",C)
    assert finish(a,'COMMIT')[0]==0
    code,out,err=finish(b);assert code==0 and out==first[0],(out,first,err)
    assert count(f'SELECT count(*) FROM booking_cancellation_events WHERE booking_id={bid};')==1
    assert count(f"SELECT count(*) FROM booking_event_outbox WHERE booking_id={bid} AND event_key LIKE 'cancelled:%';")==1
    assert count(f"SELECT count(*) FROM booking_event_notifications WHERE booking_id={bid} AND event_key LIKE 'cancelled:%';")==1
    newbid=query(actor_sql()+request_sql(3)).stdout.strip();assert newbid!=bid
    print('PASS simultaneous cancellation by both parties: one event/outbox/notification; range released',flush=True)

    k1=str(uuid.uuid4());k2=str(uuid.uuid4())
    a,_=hold(request_sql(4,k1));b=contender(request_sql(4,k2))
    assert finish(a,'ROLLBACK')[0]==0
    code,out,err=finish(b);assert code==0,err
    assert count(f"SELECT count(*) FROM booking_request_keys WHERE request_key='{k1}';")==0
    assert count("SELECT count(*) FROM bookings WHERE start_time='2036-08-04T09:00Z';")==1
    assert count(f"SELECT count(*) FROM booking_event_outbox WHERE booking_id={out};")==1
    print('PASS request rollback: blocked contender wins; no rolled-back request ledger or duplicate outbox',flush=True)

    bid=query(actor_sql()+request_sql(5)).stdout.strip()
    a,_=hold(f"SELECT booking_cancel({bid},'rollback test',NULL);")
    b=contender(request_sql(5));assert finish(a,'ROLLBACK')[0]==0
    code,out,err=finish(b);assert code and 'bookings_no_overlap' in err,err
    assert query(f'SELECT status FROM bookings WHERE id={bid};').stdout.strip()=='pending'
    assert count(f'SELECT count(*) FROM booking_cancellation_events WHERE booking_id={bid};')==0
    assert count(f"SELECT count(*) FROM booking_event_outbox WHERE booking_id={bid} AND event_key LIKE 'cancelled:%';")==0
    print('PASS cancellation rollback: original slot remains occupied; audit/outbox rollback',flush=True)

    bid=query(actor_sql()+request_sql(6)).stdout.strip()
    a,_=hold(f"SELECT booking_cancel({bid},'community cancelled',NULL);",C)
    k=str(uuid.uuid4());b=contender(f"SELECT booking_reapply({bid},1,'2036-08-06T09:00Z','2036-08-06T12:00Z','{k}');")
    assert finish(a,'COMMIT')[0]==0
    code,out,err=finish(b);assert code==0 and out!=bid,err
    assert query(f'SELECT status FROM bookings WHERE id={bid};').stdout.strip()=='cancelled'
    assert query(f'SELECT status FROM bookings WHERE id={out};').stdout.strip()=='pending'
    print('PASS cancellation/reapplication race: new ID after committed release; original history retained',flush=True)
    for role in ['anon','authenticated']:
        r=query(f'SET ROLE {role}; TRUNCATE bookings;',ok=False)
        assert r.returncode and 'permission denied' in r.stderr
    print('PASS permissions: both client roles denied TRUNCATE; 6 multi-session scenarios passed',flush=True)
finally:
    for p in sessions:
        if p.poll() is None:p.kill();p.communicate()
    if created:
        r=docker('rm','-f',NAME)
        if r.returncode:raise AssertionError(r.stderr)
        print('CLEANUP: only this temporary container and its tmpfs database removed',flush=True)
