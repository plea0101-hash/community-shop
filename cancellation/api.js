export class Api {
 constructor(config, fetcher = (...args) => fetch(...args)) {
  if (!config?.url || !config?.publishableKey) throw new Error('缺少公開連線設定');
  this.base=config.url.replace(/\/$/,''); this.key=config.publishableKey; this.fetcher=fetcher; this.token=null;
 }
 async request(path, {method='GET',body,headers={}}={}) {
  const response=await this.fetcher(this.base+path,{method,headers:{apikey:this.key,Authorization:`Bearer ${this.token || this.key}`,...(body ? {'Content-Type':'application/json'} : {}),...headers},...(body ? {body:JSON.stringify(body)} : {})});
  const data=await response.json().catch(()=>null);
  if (!response.ok) {
   if (response.status===401 && this.token) this.token=null;
   const error=new Error(response.status===401 ? '登入已失效或權限不足，請重新登入。' : data?.code==='PGRST205' || data?.code==='PGRST202' ? '取消模組尚未啟用：須先完成資料結構整合及核准 SQL 草稿。' : data?.message || `HTTP ${response.status}`);
   error.code=data?.code; throw error;
  }
  return data;
 }
 async login(email,password) {
  const session=await this.request('/auth/v1/token?grant_type=password',{method:'POST',body:{email,password}});
  this.token=session.access_token; return session.user;
 }
 async logout() {try {if(this.token) await this.request('/auth/v1/logout',{method:'POST'});} finally {this.token=null;} }
 async all(table,order='id.asc') {
  const result=[]; let offset=0;
  for (;;) {
   const rows=await this.request(`/rest/v1/${table}?select=*&order=${encodeURIComponent(order)}&limit=500&offset=${offset}`);
   if (!Array.isArray(rows)) throw new Error('資料格式不符');
   if (!rows.length) return result;
   result.push(...rows); offset+=rows.length;
   if(offset>100000) throw new Error('資料量過大，請使用伺服器分頁查詢後重試。');
  }
 }
 rpc(name,body={}) {return this.request('/rest/v1/rpc/'+name,{method:'POST',body});}
 async load() {
  const [bookings,slots,cancellations,notifications,reviews,isAdmin,policy]=await Promise.all([
   this.all('cs_bookings'),this.all('cs_slots'),this.all('cs_cancellations'),this.all('cs_notifications'),this.all('cs_typhoon_reviews'),this.rpc('cs_is_admin'),this.all('cs_policy')
  ]);
  return {bookings,slots,cancellations,notifications,reviews,isAdmin,threshold:policy[0]?.late_hours ?? null};
 }
}
