import test from 'node:test';
import assert from 'node:assert/strict';
import { checkStripeReadiness } from '../../scripts/check-stripe-readiness.mjs';

const input={apiKey:'sk_test_123456789abcdef',connectedAccountId:'acct_1234ABCD',projectRef:'ynvswdyirngvdpudcikl'};
const events=['checkout.session.completed','checkout.session.expired',
  'checkout.session.async_payment_succeeded','refund.created','refund.updated'];
const url='https://'+input.projectRef+'.supabase.co/functions/v1/stripe-webhook';
function mock({merchant=true,webhook=true,enabledEvents=events,livemode=false,
  endpoints}={}){
 const calls=[];
 const fn=async (requestUrl,init)=>{
   calls.push({url:requestUrl,method:init.method,authorization:init.headers.Authorization});
   let data;
   if(requestUrl.includes('/accounts/')){
     if(!merchant)return {ok:false,status:404};
     data={id:input.connectedAccountId,charges_enabled:true,capabilities:{card_payments:'active'}};
   }else{
     // Stripe's webhook endpoint response has no "connect" field.
     data={data:endpoints??(webhook?[{url,status:'enabled',livemode,enabled_events:enabledEvents}]:[]),has_more:false};
   }
   return {ok:true,json:async()=>data};
 };
 return {fn,calls};
}
test('observable REST configuration passes without inventing Stripe webhook connect flag',async()=>{
 const m=mock();
 const result=await checkStripeReadiness({...input,fetchImpl:m.fn});
 assert.equal(result.ready,true);
 assert.equal(result.connectScopeVerified,false);
 assert.equal(result.checks.every(x=>x.ok),true);
 assert.match(result.limitations.join(' '),/Connected accounts/);
 assert.equal(m.calls.length,2);
 assert.equal(m.calls.every(x=>x.method==='GET'),true);
 assert.equal(m.calls.every(x=>x.authorization.startsWith('Bearer sk_test_')),true);
});
test('no false-negative when the webhook JSON does not expose connect property',async()=>{
 const m=mock({endpoints:[{url,status:'enabled',livemode:false,enabled_events:events}]});
 const result=await checkStripeReadiness({...input,fetchImpl:m.fn});
 assert.equal(result.ready,true);
 assert.equal(result.connectScopeVerified,false);
});
test('release gate fails when platform API key cannot read the school merchant',async()=>{
 const r=await checkStripeReadiness({...input,fetchImpl:mock({merchant:false}).fn});
 assert.equal(r.ready,false);
 assert.match(r.checks[0].name,/Account Connect/);
});
test('release gate rejects unrelated, absent, or live-mode webhook endpoints',async()=>{
 for(const options of [{webhook:false},{livemode:true},
   {endpoints:[{url:'https://unrelated.example/webhook',status:'enabled',livemode:false,enabled_events:events}]}]){
   const r=await checkStripeReadiness({...input,fetchImpl:mock(options).fn});
   assert.equal(r.ready,false);
 }
});
test('release gate refuses partial webhook event coverage',async()=>{
 const r=await checkStripeReadiness({...input,fetchImpl:mock({enabledEvents:['checkout.session.completed']}).fn});
 assert.equal(r.ready,false);
 assert.equal(r.checks.find(x=>x.name.includes('refund.updated')).ok,false);
});
test('events must be enabled on a single active endpoint, not scattered across endpoints',async()=>{
 const r=await checkStripeReadiness({...input,fetchImpl:mock({endpoints:[
   {url,status:'enabled',livemode:false,enabled_events:events.slice(0,3)},
   {url,status:'enabled',livemode:false,enabled_events:events.slice(3)}
 ]}).fn});
 assert.equal(r.ready,false);
 assert.equal(r.checks.at(-1).ok,false);
});
test('release gate rejects duplicate active destinations sharing the same signing URL',async()=>{
 const r=await checkStripeReadiness({...input,fetchImpl:mock({endpoints:[
   {id:'we_new',url,status:'enabled',livemode:false,enabled_events:events},
   {id:'we_old',url,status:'enabled',livemode:false,enabled_events:events.slice(0,3)}
 ]}).fn});
 assert.equal(r.ready,false);
 assert.equal(r.matchingEndpoints,2);
 assert.equal(r.activeMatchingEndpoints,2);
 assert.equal(r.checks.find(x=>x.name.includes('Esattamente un webhook')).ok,false);
 assert.equal(r.checks.at(-1).ok,true);
});
test('disabled legacy webhook may coexist with the only complete active endpoint',async()=>{
 const r=await checkStripeReadiness({...input,fetchImpl:mock({endpoints:[
   {id:'we_new',url,status:'enabled',livemode:false,enabled_events:events},
   {id:'we_old',url,status:'disabled',livemode:false,enabled_events:events.slice(0,3)}
 ]}).fn});
 assert.equal(r.ready,true);
 assert.equal(r.matchingEndpoints,2);
 assert.equal(r.activeMatchingEndpoints,1);
 assert.equal(r.checks.find(x=>x.name.includes('Esattamente un webhook')).ok,true);
});
test('release gate refuses live keys and invalid project identifiers',async()=>{
 const unreachable=()=>{throw Error('should not fetch');};
 await assert.rejects(checkStripeReadiness({...input,apiKey:'sk_live_1234567',fetchImpl:unreachable}),/TEST/);
 await assert.rejects(checkStripeReadiness({...input,projectRef:'https://example.org',fetchImpl:unreachable}),/Supabase/);
});
