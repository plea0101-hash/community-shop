"""Local-only UI tests. Every Supabase request is intercepted; no live API writes."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse, parse_qs
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
now = datetime.now(timezone.utc)
start = (now + timedelta(hours=12)).isoformat()
end = (now + timedelta(hours=15)).isoformat()
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs): super().__init__(*args, directory=str(ROOT), **kwargs)
    def log_message(self, *_): pass
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
Thread(target=server.serve_forever, daemon=True).start()
state = {
 'cs_slots':[{'id':'s1','venue_ref':'合成場地','community_user_id':'community','starts_at':start,'ends_at':end}],
 'cs_bookings':[{'id':'b1','slot_id':'s1','vendor_user_id':'vendor','community_user_id':'community','label':'合成預約 <img src=x onerror=window.XSS=true>','status':'confirmed'}],
 'cs_cancellations':[], 'cs_typhoon_reviews':[], 'cs_notifications':[], 'cs_policy':[{'id':True,'late_hours':24}]
}
current = {'id':'vendor'}
calls=[]
def route_request(route):
    request=route.request
    url=urlparse(request.url)
    if url.hostname in ('127.0.0.1','localhost'):
        route.continue_();return
    # All non-local traffic is fulfilled or aborted, never forwarded.
    if not url.hostname.endswith('.supabase.co'):
        route.abort();return
    path=url.path
    payload=request.post_data_json if request.post_data else {}
    calls.append((request.method,path))
    if request.method=='OPTIONS':
        route.fulfill(status=204,headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*','Access-Control-Allow-Methods':'GET,POST,OPTIONS'});return
    result=None
    if path=='/auth/v1/token':
        current['id']=payload['email'].split('@')[0]
        result={'access_token':'synthetic-session','user':{'id':current['id'],'email':payload['email']}}
    elif path=='/auth/v1/logout':result={}
    elif path.endswith('/rpc/cs_is_admin'):result=current['id']=='admin'
    elif path.endswith('/rpc/cs_cancel_booking'):
        booking=next(b for b in state['cs_bookings'] if b['id']==payload['p_booking_id'])
        booking['status']='cancelled'
        ev=payload.get('p_typhoon') or {}
        c={'id':'cancel1','booking_id':booking['id'],'actor_id':current['id'],'actor_side':current['id'], 'original_status':'confirmed','status':'cancelled','original_starts_at':start,'original_ends_at':end,'cancelled_at':now.isoformat(),'hours_before_start':12,'late_hours_snapshot':24,'timing':'late','reason':payload['p_reason'],'typhoon_status':'pending' if ev else 'none',**ev}
        state['cs_cancellations'].append(c)
        state['cs_notifications'].append({'id':'n1','recipient_id':'community','booking_id':booking['id'],'cancellation_id':c['id'],'kind':'cancelled','created_at':now.isoformat(),'read_at':None})
        result=c['id']
    elif path.endswith('/rpc/cs_review_typhoon'):
        c=state['cs_cancellations'][0]
        c['typhoon_status']='pending' if payload['p_verified'] is None else 'verified' if payload['p_verified'] else 'rejected'
        state['cs_typhoon_reviews'].append({'id':'r'+str(len(state['cs_typhoon_reviews'])),'cancellation_id':c['id'],'reviewer_id':'admin','reviewed_at':now.isoformat(),'decision':c['typhoon_status'],'note':payload['p_note']})
    elif path.endswith('/rpc/cs_reapply'):
        state['cs_bookings'].append({'id':'b2','slot_id':'s1','vendor_user_id':'vendor','community_user_id':'community','label':'新申請','status':'pending','reapplied_from':'b1'})
        result='b2'
    elif path.endswith('/rpc/cs_read_notification'):
        state['cs_notifications'][0]['read_at']=now.isoformat()
    elif '/rest/v1/' in path:
        table=path.rsplit('/',1)[-1]
        rows=state.get(table,[])
        if table=='cs_notifications': rows=[r for r in rows if r['recipient_id']==current['id']]
        if int(parse_qs(url.query).get('offset',['0'])[0])>0: rows=[]
        result=rows
    else:raise AssertionError('Unexpected external request: '+path)
    route.fulfill(status=200,content_type='application/json',headers={'Access-Control-Allow-Origin':'*'},body=json.dumps(result))

def login(page, role):
    page.locator('#login input[name=email]').fill(role+'@example.invalid')
    page.locator('#login input[name=password]').fill('synthetic-password')
    page.locator('#login button').click()
    
    try: page.locator('#workspace').wait_for(state='visible',timeout=5000)
    except Exception:
        print('UI diagnostic:',page.locator('#message').inner_text(),calls,flush=True)
        raise

def logout(page):
    page.locator('#logout').click();page.locator('#login').wait_for(state='visible')

try:
 with sync_playwright() as p:
    browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
    context=browser.new_context()
    context.route('**/*',route_request)
    page=context.new_page();errors=[]
    page.on('pageerror',lambda e:(errors.append(str(e)),print('JS ERROR:',str(e),flush=True)))
    page.goto(f'http://127.0.0.1:{server.server_port}/cancellation/')
    login(page,'vendor')
    assert page.locator('#admin-tab').is_hidden()
    assert page.locator('#content img').count()==0
    assert page.evaluate('window.XSS') is None
    page.locator('[data-cancel]').click()
    assert page.locator('#cancel-form textarea').get_attribute('required') is not None
    page.locator('#cancel-form textarea').fill('合成颱風取消原因')
    page.locator('[name=typhoon]').check()
    page.locator('[name=source_url]').fill('https://www.dgpa.gov.tw/test-only')
    page.locator('[name=announced_on]').fill(now.astimezone(timezone(timedelta(hours=8))).date().isoformat())
    page.locator('[name=county]').select_option(label='連江縣')
    page.locator('[name=suspension]').select_option('school')
    page.locator('[name=confirmed]').check()
    page.locator('#cancel-form button[type=submit]').click()
    page.locator('#cancel-dialog').wait_for(state='hidden')
    assert state['cs_bookings'][0]['status']=='cancelled'
    page.get_by_text('颱風待審核（暫不計入）',exact=False).first.wait_for()
    page.locator('[data-reapply]').click()
    page.locator('#reapply-form select').select_option('s1')
    page.locator('#reapply-form button[type=submit]').click()
    page.locator('#reapply-dialog').wait_for(state='hidden')
    assert state['cs_bookings'][1]['status']=='pending'
    print('PASS vendor: login, XSS escaping, late reason, typhoon school claim, cancellation, reapplication')
    logout(page);login(page,'community')
    page.locator('[data-view=community]').click()
    assert page.locator('[data-cancel]').count()==1
    page.locator('[data-view=notifications]').click()
    assert page.get_by_text('對方已取消預約').count()==1
    page.locator('[data-read]').click()
    page.get_by_text('已讀',exact=False).wait_for()
    print('PASS community: bookings and cancellation notification/read state')
    logout(page);login(page,'admin')
    page.locator('[data-view=admin]').click()
    assert page.locator('[data-review]').count()==1
    page.locator('[data-review]').click()
    dialog=page.locator('dialog[open]')
    dialog.locator('[name=decision]').select_option('pending')
    dialog.locator('[name=note]').fill('合成來源暫無法驗證')
    dialog.locator('[name=checked]').check()
    dialog.locator('button[type=submit]').click()
    dialog.wait_for(state='hidden')
    assert state['cs_cancellations'][0]['typhoon_status']=='pending'
    page.locator('[data-review]').click()
    dialog=page.locator('dialog[open]')
    dialog.locator('[name=decision]').select_option('verified')
    dialog.locator('[name=note]').fill('合成查核通過')
    dialog.locator('[name=checked]').check()
    dialog.locator('button[type=submit]').click()
    dialog.wait_for(state='hidden')
    assert state['cs_cancellations'][0]['typhoon_status']=='verified'
    page.get_by_text('颱風特殊取消（已核驗）',exact=False).first.wait_for()
    page.locator('#filters select[name=typhoon]').select_option('pending')
    page.locator('#filters button').click()
    page.get_by_text('沒有符合條件的取消紀錄').wait_for()
    page.set_viewport_size({'width':390,'height':844})
    assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
    assert not errors,errors
    assert all(method in ('GET','POST','OPTIONS') for method,_ in calls)
    print('PASS admin: pending review, verified exemption, audit, filters, mobile; JS errors=0')
    print('All external requests intercepted; live Supabase writes=0')
    browser.close()
finally:server.shutdown()
