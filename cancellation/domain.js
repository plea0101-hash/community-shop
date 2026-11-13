export const counties = ['臺北市','新北市','桃園市','臺中市','臺南市','高雄市','基隆市','新竹市','嘉義市','新竹縣','苗栗縣','彰化縣','南投縣','雲林縣','嘉義縣','屏東縣','宜蘭縣','花蓮縣','臺東縣','澎湖縣','金門縣','連江縣'];
export const labels = {
 pending:'待審核', confirmed:'已確認', cancelled:'已取消',
 general:'一般取消', late:'臨時取消', unclassified:'待分類（門檻未確認）',
 none:'非颱風主張', verified:'颱風特殊取消（已核驗）', rejected:'颱風主張未通過',
 vendor:'廠商', community:'社區', work:'停班', school:'停課', both:'停班及停課'
};
export function taipeiDate(value) {
 const date = new Date(value);
 if (!Number.isFinite(date.getTime())) throw new Error('無效日期');
 return new Intl.DateTimeFormat('en-CA', {timeZone:'Asia/Taipei', year:'numeric', month:'2-digit', day:'2-digit'}).format(date);
}
export function formatTime(value) {
 return new Intl.DateTimeFormat('zh-TW', {timeZone:'Asia/Taipei',dateStyle:'medium',timeStyle:'short',hour12:false}).format(new Date(value));
}
export function classify(startsAt, cancelledAt, threshold) {
 const hours = (new Date(startsAt)-new Date(cancelledAt))/3600000;
 if (!Number.isFinite(hours)) throw new Error('無效日期');
 if (threshold !== null && threshold !== undefined && (!Number.isFinite(Number(threshold)) || Number(threshold)<=0)) throw new Error('無效門檻');
 return {hours, timing: threshold == null ? 'unclassified' : hours <= Number(threshold) ? 'late' : 'general'};
}
export function validateEvidence(evidence, startsAt, now = new Date()) {
 let url;
 try { url = new URL(evidence.source_url); } catch { throw new Error('請提供官方公告網址'); }
 if (url.protocol !== 'https:' || !(url.hostname === 'gov.tw' || url.hostname.endsWith('.gov.tw')) || url.username || url.password || evidence.source_url.length>2000) throw new Error('請提供 HTTPS 政府 gov.tw 官方來源');
 if (!/^\d{4}-\d{2}-\d{2}$/.test(evidence.announced_on) || Number.isNaN(Date.parse(evidence.announced_on)) || evidence.announced_on > taipeiDate(now)) throw new Error('公告日期無效或尚未到達');
 if (evidence.applicable_on !== taipeiDate(startsAt)) throw new Error('適用日期必須涵蓋原活動的臺灣日期');
 if (!counties.includes(evidence.county) || !['work','school','both'].includes(evidence.suspension)) throw new Error('請選擇正式宣布停班或停課的臺灣縣市');
 return evidence;
}
export function countsAsLate(c) {
 return c.timing === 'late' && ['none','rejected'].includes(c.typhoon_status);
}
export function filterRecords(records, {from='',to='',actor='',side='',timing='',typhoon=''} = {}) {
 return records.filter(c => {
  const date = taipeiDate(c.cancelled_at);
  return (!from || date>=from) && (!to || date<=to) && (!actor || c.actor_id.includes(actor)) && (!side || c.actor_side===side) && (!timing || c.timing===timing) && (!typhoon || c.typhoon_status===typhoon);
 });
}
export function statistics(records, bookings = []) {
 const grouped = new Map();
 for (const c of records) {
  const key = `${c.actor_id}:${c.actor_side}`;
  const row = grouped.get(key) || {actor:c.actor_id,side:c.actor_side,total:0,late:0,exempt:0,pending:0,unclassified:0};
  row.total++;
  if (countsAsLate(c)) row.late++;
  if (c.typhoon_status==='verified') row.exempt++;
  if (c.typhoon_status==='pending') row.pending++;
  if (c.timing==='unclassified') row.unclassified++;
  // A count ranking is evidence for review, never an automatic penalty decision.
  grouped.set(key,row);
 }
 return [...grouped.values()].map(row=>({...row,bookings:bookings.filter(b=>b[row.side==='vendor'?'vendor_user_id':'community_user_id']===row.actor).length})).sort((a,b)=>b.total-a.total || a.actor.localeCompare(b.actor));
}
export const esc = value => String(value ?? '').replace(/[&<>"']/g, char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
