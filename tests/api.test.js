import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Api} from '../cancellation/api.js';
const config={url:'https://example.supabase.co',publishableKey:'public-test-key'};
test('authentication token is memory-only and forwarded instead of public key',async()=>{
 const calls=[];const api=new Api(config,async(url,options)=>{calls.push({url,...options});return {ok:true,json:async()=>url.includes('/token?')?{access_token:'test-session',user:{id:'u1'}}:[]};});
 await api.login('test@example.invalid','fake-password');await api.all('cs_bookings');
 assert.equal(calls[1].headers.Authorization,'Bearer test-session');
 await api.logout();assert.equal(api.token,null);
});
test('pagination does not truncate silently at server maximum',async()=>{
 let count=0;const api=new Api(config,async()=>({ok:true,json:async()=>++count<3?[{id:count}]:[]}));
 assert.equal((await api.all('cs_cancellations')).length,2);assert.equal(count,3);
});
test('missing migration and expired session produce actionable failure',async()=>{
 const api=new Api(config,async()=>({ok:false,status:404,json:async()=>({code:'PGRST205'})}));
 await assert.rejects(api.all('cs_bookings'),/尚未啟用/);
 api.token='expired';api.fetcher=async()=>({ok:false,status:401,json:async()=>({})});
 await assert.rejects(api.all('cs_bookings'),/重新登入/);assert.equal(api.token,null);
});
