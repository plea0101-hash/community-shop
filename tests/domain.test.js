import {test} from 'node:test';
import assert from 'node:assert/strict';
import {classify,taipeiDate,validateEvidence,countsAsLate,statistics,filterRecords,esc} from '../cancellation/domain.js';
const start='2030-08-01T17:00:00+08:00';
test('inclusive 24-hour boundary without rounding; nullable policy safe fallback',()=>{
 assert.equal(classify(start,'2030-07-31T17:00:00+08:00',24).timing,'late');
 assert.equal(classify(start,'2030-07-31T16:59:59.999+08:00',24).timing,'general');
 assert.equal(classify(start,'2030-07-31T17:00:00.001+08:00',24).timing,'late');
 assert.equal(classify(start,'2030-07-31T17:00:00+08:00',null).timing,'unclassified');
 assert.throws(()=>classify(start,'invalid',24));assert.throws(()=>classify(start,start,0));
});
test('Taiwan date and national county eligibility; school-only is sufficient',()=>{
 assert.equal(taipeiDate('2030-08-01T16:01:00Z'),'2030-08-02');
 const evidence={source_url:'https://www.dgpa.gov.tw/typhoon',announced_on:'2030-07-31',applicable_on:'2030-08-01',county:'連江縣',suspension:'school'};
 assert.equal(validateEvidence(evidence,start,new Date('2030-07-31T16:00:00Z')),evidence);
 for(const patch of [{source_url:'https://gov.tw.evil.test/'},{source_url:'javascript:alert(1)'},{source_url:'https://evil@gov.tw/'},{county:'國外'},{applicable_on:'2030-08-02'},{announced_on:'2030-08-03'},{suspension:'rain'}])assert.throws(()=>validateEvidence({...evidence,...patch},start,new Date('2030-08-01')));
});
test('pending and verified typhoons excluded; rejected restores timing; no punishment rules',()=>{
 const base={actor_id:'vendor1',actor_side:'vendor',timing:'late',cancelled_at:'2030-07-31T17:00:00Z'};
 const records=['none','pending','verified','rejected'].map(typhoon_status=>({...base,typhoon_status}));
 assert.deepEqual(records.map(countsAsLate),[true,false,false,true]);
 const stats=statistics(records)[0];assert.equal(stats.total,4);assert.equal(stats.late,2);assert.equal(stats.exempt,1);assert.equal(stats.pending,1);
 assert.equal(filterRecords(records,{from:'2030-08-01',to:'2030-08-01',typhoon:'pending'}).length,1);
 assert.equal(filterRecords(records,{side:'community'}).length,0);
 assert.equal(countsAsLate({...base,timing:'unclassified',typhoon_status:'rejected'}),false);
});
test('untrusted content is escaped',()=>assert.equal(esc('<script>"&\''),'&lt;script&gt;&quot;&amp;&#39;'));
