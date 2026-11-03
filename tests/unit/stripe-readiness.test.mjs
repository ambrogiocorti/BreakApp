import test from 'node:test';
import assert from 'node:assert/strict';
import { checkStripeReadiness } from '../../scripts/check-stripe-readiness.mjs';

const input={apiKey:'sk_test_123456789abcdef',connectedAccountId:'acct_1234ABCD',projectRef:'ynvswdyirngvdpudcikl'};
const events=['checkout.session.completed','checkout.session.expired',
  'checkout.session.async_payment_succeeded','refund.created','refund.updated'];
function mock({merchant=true,webhook=true,connect=true,enabledEvents=events}={}){
 const calls=[];
 const fn=async (url,init)=>{
   calls.push({url,method:init.method,authorization:init.headers.Authorization});
   let data;
   if(url.includes('/accounts/')){
     if(!merchant)return {ok:false,status:404};
     data={id:input.connectedAccountId,charges_enabled:true,capabilities:{card_payments:'active'}};
   }else{
     data={data:webhook?[{url:'https://'+input.projectRef+'.supabase.co/functions/v1/stripe-webhook',
       status:'enabled',connect,enabled_events:enabledEvents}]:[],has_more:false};
   }
   return {ok:true,json:async()=>data};
 };
 return {fn,calls};
}
test('release gate accepts only a consistent TEST Connect platform with a signed-event destination',async()=>{
 const m=mock();
 const result=await checkStripeReadiness({...input,fetchImpl:m.fn});
 assert.equal(result.ready,true);
 assert.equal(result.checks.every(x=>x.ok),true);
 assert.equal(m.calls.length,2);
 assert.equal(m.calls.every(x=>x.method==='GET'),true);
 assert.equal(m.calls.every(x=>x.authorization.startsWith('Bearer sk_test_')),true);
 assert.match(result.limitations.join(' '),/webhook/i);
});
test('release gate fails when platform API key cannot read the linked school merchant',async()=>{
 const r=await checkStripeReadiness({...input,fetchImpl:mock({merchant:false}).fn});
 assert.equal(r.ready,false);
 assert.match(r.checks[0].name,/Account Connect/);
});
test('release gate rejects unrelated project webhooks and non-Connect destinations',async()=>{
 for(const options of [{webhook:false},{connect:false}]){
   const r=await checkStripeReadiness({...input,fetchImpl:mock(options).fn});
   assert.equal(r.ready,false);
 }
});
test('release gate refuses partial webhook event coverage',async()=>{
 const r=await checkStripeReadiness({...input,fetchImpl:mock({enabledEvents:['checkout.session.completed']}).fn});
 assert.equal(r.ready,false);
 assert.equal(r.checks.find(x=>x.name.includes('refund.updated')).ok,false);
});
test('release gate does not contact Stripe with live keys or invalid project identifiers',async()=>{
 const unreachable=()=>{throw Error('should not fetch');};
 await assert.rejects(checkStripeReadiness({...input,apiKey:'sk_live_1234567',fetchImpl:unreachable}),/TEST/);
 await assert.rejects(checkStripeReadiness({...input,projectRef:'https://example.org',fetchImpl:unreachable}),/Supabase/);
});
