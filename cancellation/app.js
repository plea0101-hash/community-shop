import {Api} from './api.js';
import {esc,labels,counties,formatTime,taipeiDate,classify,validateEvidence,filterRecords,statistics,countsAsLate} from './domain.js';
const $ = selector=>document.querySelector(selector);
const api=new Api(window.COMMUNITY_SHOP_CONFIG);
let user=null, data=null, view='vendor', activeBooking=null, busy=false;
const name=value=>labels[value] || value;
const message=text=>{$('#message').textContent=text;};
const slot=b=>data.slots.find(s=>s.id===b.slot_id);
const safeUrl=value=>{try{const u=new URL(value);return u.protocol==='https:' && (u.hostname==='gov.tw'||u.hostname.endsWith('.gov.tw')) && !u.username && !u.password ? u.href : null;}catch{return null;}};
function evidenceLink(c){const url=safeUrl(c.source_url);return url?`<a href="${esc(url)}" target="_blank" rel="noopener noreferrer">官方公告來源</a>`:'無有效官方來源';}
function cancellationKind(c){return c.typhoon_status==='verified' ? name('verified') : `${name(c.timing)}／${c.typhoon_status==='pending'?'颱風待審核（暫不計入）':name(c.typhoon_status)}`;}
async function refresh(){
 const next=await api.load(); data=next;
 $('#admin-tab').hidden=!data.isAdmin;
 $('#identity').textContent=user.email || user.id;
 $('#workspace').hidden=false; $('#login').hidden=true;
 render();
}
async function action(task){
 if(busy)return;busy=true;
 document.querySelectorAll('button').forEach(b=>b.disabled=true);
 try{await task();}catch(e){message(e.message);if(!api.token)clearSession();}
 finally{busy=false;document.querySelectorAll('button').forEach(b=>b.disabled=false);}
}
function clearSession(){user=null;data=null;$('#workspace').hidden=true;$('#content').replaceChildren();$('#identity').textContent='';$('#login').hidden=false;document.querySelectorAll('dialog[open]').forEach(d=>d.close());}
$('#login').addEventListener('submit',e=>{
 e.preventDefault();const form=e.currentTarget;const fields=new FormData(form);
 action(async()=>{user=await api.login(fields.get('email'),fields.get('password'));form.reset();await refresh();message('已登入。取消判定由伺服器時間及權限驗證。');});
});
$('#logout').onclick=()=>action(async()=>{try{await api.logout();}finally{clearSession();message('已登出');}});
$('#refresh').onclick=()=>action(async()=>{await refresh();message('已重新讀取最新資料。');});
document.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>{view=b.dataset.view;render();});
document.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>document.getElementById(b.dataset.close).close());
function render(){
 document.querySelectorAll('[data-view]').forEach(b=>b.setAttribute('aria-current',String(b.dataset.view===view)));
 if(view==='vendor'||view==='community')renderBookings();
 else if(view==='notifications')renderNotifications();
 else if(view==='admin'&&data.isAdmin)renderHistory(true);
 else renderHistory(false);
}
function renderBookings(){
 const side=view==='vendor'?'vendor_user_id':'community_user_id';
 const rows=data.bookings.filter(b=>b[side]===user.id);
 $('#content').innerHTML=`<h2>${view==='vendor'?'廠商':'社區'}：我的預約</h2><p>取消距活動開始 ≤24 小時屬臨時取消，超過 24 小時屬一般取消；不自動處罰。</p>${!rows.length?'<p>目前沒有你的預約。</p>':rows.map(b=>{
 const s=slot(b); const c=data.cancellations.find(c=>c.booking_id===b.id);
 return `<article class="card"><h3>${esc(b.label)}</h3><small>預約編號：${esc(b.id)}</small><p>${s?esc(formatTime(s.starts_at))+' 至 '+esc(formatTime(s.ends_at)):'時段資訊待確認'}</p><p>狀態：${esc(name(b.status))}</p>${c?`<p>${esc(cancellationKind(c))}，取消原因：${esc(c.reason||'未填寫')}</p><p>取消於 ${esc(formatTime(c.cancelled_at))}，距活動開始 ${Number(c.hours_before_start).toFixed(2)} 小時</p>`:''}<div class="actions">${b.status!=='cancelled'&&s?`<button data-cancel="${esc(b.id)}">取消預約</button>`:''}${b.status==='cancelled'?`<button data-reapply="${esc(b.id)}">重新申請</button>`:''}</div></article>`;
 }).join('')}`;
}
function recordTable(records,admin){
 return `<div class="table"><table><thead><tr><th>預約／取消者</th><th>原活動／取消時間</th><th>分類與原因</th><th>颱風公告／查核</th></tr></thead><tbody>${records.map(c=>{
 const reviews=data.reviews.filter(r=>r.cancellation_id===c.id).sort((a,b)=>new Date(a.reviewed_at)-new Date(b.reviewed_at));
 return `<tr><td>${esc(c.booking_id)}<small>${esc(name(c.actor_side))}：${esc(c.actor_id)}</small><small>取消狀態：${esc(name(c.status))}；原狀態：${esc(name(c.original_status))}</small></td><td>${esc(formatTime(c.original_starts_at))} 至 ${esc(formatTime(c.original_ends_at))}<small>取消：${esc(formatTime(c.cancelled_at))}</small><small>距開始 ${Number(c.hours_before_start).toFixed(2)} 小時；門檻 ${esc(c.late_hours_snapshot??'未設定')} 小時</small></td><td>${esc(cancellationKind(c))}<small>${esc(c.reason||'未填寫')}</small><small>${countsAsLate(c)?'列入一般臨時取消查核次數':'不列入一般臨時取消查核次數'}</small></td><td>${c.typhoon_status==='none'?'—':`${evidenceLink(c)}<small>${esc(c.county)}／${esc(name(c.suspension))}</small><small>公告：${esc(c.announced_on)}；適用：${esc(c.applicable_on)}</small>${reviews.map(review=>`<small>查核：${esc(formatTime(review.reviewed_at))}；${esc(review.reviewer_id)}；${esc(review.decision)}；${esc(review.note)}</small>`).join('')}${admin&&c.typhoon_status==='pending'?`<button data-review="${esc(c.id)}">查核此公告</button>`:''}`}</td></tr>`;
 }).join('')||'<tr><td colspan="4">沒有符合條件的取消紀錄</td></tr>'}</tbody></table></div>`;
}
function renderHistory(admin){
 $('#content').innerHTML=`<h2>${admin?'管理員：取消紀錄、颱風查核與異常頻率':'取消紀錄'}</h2><form id="filters"><div class="filters"><label>取消起日<input type="date" name="from"></label><label>取消迄日<input type="date" name="to"></label><label>取消者 ID<input name="actor"></label><label>取消身分<select name="side"><option value="">全部</option><option value="vendor">廠商</option><option value="community">社區</option></select></label><label>時間分類<select name="timing"><option value="">全部</option>${['general','late','unclassified'].map(t=>`<option value="${t}">${name(t)}</option>`).join('')}</select></label><label>颱風查核<select name="typhoon"><option value="">全部</option><option value="pending">待審核</option><option value="verified">已核驗</option><option value="rejected">未通過</option><option value="none">非颱風主張</option></select></label></div><button>查詢</button></form><div id="stats"></div><div id="records"></div>`;
 const update=()=>{
  const filters=Object.fromEntries(new FormData($('#filters')));
  if(filters.from&&filters.to&&filters.from>filters.to){message('起日不能晚於迄日');return;}
  const allowed=admin?data.cancellations:data.cancellations.filter(c=>data.bookings.some(b=>b.id===c.booking_id&&(b.vendor_user_id===user.id||b.community_user_id===user.id)));
  const rows=filterRecords(allowed,filters);
  $('#records').innerHTML=recordTable(rows,admin);
  const stats=statistics(rows,data.bookings);
  $('#stats').innerHTML=admin?`<p>下列為查詢範圍內的取消次數排名，供人工辨識異常；沒有自動處罰或未確認的異常門檻。待審颱風暫不計入，未通過時恢復原時間分類。</p><div class="table"><table><thead><tr><th>取消者／身分</th><th>取消總數</th><th>一般臨時取消次數</th><th>颱風豁免</th><th>颱風待審</th><th>待分類</th></tr></thead><tbody>${stats.map(s=>`<tr><td>${esc(s.actor)}<small>${name(s.side)}</small></td><td>${s.total}</td><td>${s.late}</td><td>${s.exempt}</td><td>${s.pending}</td><td>${s.unclassified}</td></tr>`).join('')}</tbody></table></div>`:'';
 };
 $('#filters').onsubmit=e=>{e.preventDefault();update();};update();
}
function renderNotifications(){
 $('#content').innerHTML=`<h2>通知</h2><p>取消時在同一交易寫入對方的頁內收件匣；此版本不寄送 email 或簡訊。</p>${data.notifications.map(n=>`<article class="card"><h3>${esc({cancelled:'對方已取消預約',typhoon_review:'颱風查核結果已更新',reapplied:'收到重新申請'}[n.kind])}</h3><p>預約：${esc(n.booking_id)}</p><p>${esc(formatTime(n.created_at))} · ${n.read_at?'已讀':'未讀'}</p>${n.cancellation_id?`<button data-history>查看取消原因與查核紀錄</button>`:''}${!n.read_at?` <button data-read="${esc(n.id)}">標記已讀</button>`:''}</article>`).join('')||'<p>目前沒有通知。</p>'}`;
}
$('#content').addEventListener('click',e=>{
 const b=e.target.closest('button');if(!b||busy)return;
 if(b.dataset.cancel)openCancel(b.dataset.cancel);
 if(b.dataset.reapply)openReapply(b.dataset.reapply);
 if(b.hasAttribute('data-history')){view='history';render();}
 if(b.dataset.read)action(async()=>{await api.rpc('cs_read_notification',{p_id:b.dataset.read});await refresh();});
 if(b.dataset.review)openReview(b.dataset.review);
});
function openCancel(id){
 activeBooking=data.bookings.find(b=>b.id===id);const s=slot(activeBooking);
 const info=classify(s.starts_at,new Date(),data.threshold);
 $('#cancel-form').reset();$('#cancel-error').textContent='';$('#evidence').hidden=true;
 for(const n of ['source_url','announced_on','applicable_on','county','suspension'])$('#cancel-form').elements[n].required=false;
 $('#cancel-form').elements.reason.required=info.timing!=='general';
 $('#cancel-summary').innerHTML=`<p>${esc(activeBooking.label)}：${esc(formatTime(s.starts_at))}</p><p>目前預估：${esc(name(info.timing))}，距開始 ${info.hours.toFixed(2)} 小時。最終依伺服器確認時刻判定。</p>`;
 $('#cancel-form').elements.applicable_on.value=taipeiDate(s.starts_at);
 $('#cancel-dialog').showModal();
}
$('#cancel-form').elements.county.innerHTML=counties.map(c=>`<option>${c}</option>`).join('');
$('#cancel-form').elements.typhoon.onchange=e=>{
 $('#evidence').hidden=!e.target.checked;
 for(const n of ['source_url','announced_on','applicable_on','county','suspension'])$('#cancel-form').elements[n].required=e.target.checked;
 const info=classify(slot(activeBooking).starts_at,new Date(),data.threshold);
 $('#cancel-form').elements.reason.required=e.target.checked||info.timing!=='general';
};
$('#cancel-form').onsubmit=e=>{
 e.preventDefault();const f=new FormData(e.currentTarget);
 action(async()=>{
  try{
   const evidence=f.has('typhoon')?validateEvidence(Object.fromEntries(['source_url','announced_on','applicable_on','county','suspension'].map(k=>[k,f.get(k)])),slot(activeBooking).starts_at):null;
   await api.rpc('cs_cancel_booking',{p_booking_id:activeBooking.id,p_reason:f.get('reason').trim(),p_typhoon:evidence});
   $('#cancel-dialog').close();await refresh();message('預約已取消，原時段已釋出，已寫入對方頁內通知。');
  }catch(error){$('#cancel-error').textContent=error.message;throw error;}
 });
};
function openReapply(id){
 activeBooking=data.bookings.find(b=>b.id===id);
 const free=data.slots.filter(s=>(view!=='community'||s.community_user_id===user.id)&&new Date(s.starts_at)>new Date()&&!data.bookings.some(b=>b.slot_id===s.id&&['pending','confirmed'].includes(b.status)));
 // RLS may hide other parties' bookings; availability is rechecked and locked server-side.
 $('#reapply-form').elements.slot.innerHTML='<option value="">請選擇（送出時重新確認空檔）</option>'+free.map(s=>`<option value="${esc(s.id)}">${esc(s.venue_ref)} · ${esc(formatTime(s.starts_at))}</option>`).join('');
 $('#reapply-error').textContent='';$('#reapply-dialog').showModal();
}
$('#reapply-form').onsubmit=e=>{
 e.preventDefault();const chosen=new FormData(e.currentTarget).get('slot');
 action(async()=>{try{await api.rpc('cs_reapply',{p_cancelled_booking_id:activeBooking.id,p_slot_id:chosen});$('#reapply-dialog').close();await refresh();message('新的待審核申請已建立，原取消紀錄保留。');}catch(error){$('#reapply-error').textContent=error.message;throw error;}});
};
function openReview(id){
 const c=data.cancellations.find(c=>c.id===id);
 const d=document.createElement('dialog');
 d.innerHTML=`<form><h2>颱風特殊取消查核</h2><p>${evidenceLink(c)}</p><p>${esc(c.county)}，${esc(name(c.suspension))}；公告 ${esc(c.announced_on)}，適用 ${esc(c.applicable_on)}</p><p>請人工確認政府正式公告因颱風停班或停課，且涵蓋原活動的臺灣日期。任一縣市均適用；URL 本身不代表已核驗。</p><label>查核決定<select name="decision"><option value="">請選擇</option><option value="verified">官方公告已核驗，列颱風特殊取消</option><option value="pending">目前無法驗證，保留待審核</option><option value="rejected">已確認不符合條件</option></select></label><label>查核依據／不通過原因<textarea name="note" required maxlength="2000"></textarea></label><label class="check"><input name="checked" type="checkbox" required>我已查閱官方來源並確認本次決定</label><p role="alert"></p><button type="button">返回</button><button type="submit">儲存查核</button></form>`;
 d.querySelector('select').required=true;d.querySelector('button[type=button]').onclick=()=>d.close();d.addEventListener('close',()=>d.remove());
 d.querySelector('form').onsubmit=e=>{e.preventDefault();const f=new FormData(e.currentTarget);action(async()=>{try{await api.rpc('cs_review_typhoon',{p_cancellation_id:id,p_verified:f.get('decision')==='pending'?null:f.get('decision')==='verified',p_note:f.get('note').trim()});d.close();await refresh();message('查核已保存，雙方已收到頁內通知。');}catch(error){d.querySelector('[role=alert]').textContent=error.message;throw error;}});};
 document.body.append(d);d.showModal();
}
