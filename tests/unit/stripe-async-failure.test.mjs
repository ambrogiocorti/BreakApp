import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac,webcrypto} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
import {runInNewContext} from 'node:vm';

const secret='whsec_test_only_for_unit_tests';
const attempt='90000000-0000-4000-8000-000000000001';
const original={
 id:'evt_asyncFailureTest1',livemode:false,type:'checkout.session.async_payment_failed',
 account:'acct_TestSchool1',data:{object:{
  id:'cs_test_AsyncFailure1',object:'checkout.session',mode:'payment',
  payment_status:'unpaid',currency:'eur',amount_total:250,
  payment_intent:'pi_AsyncFailure1',client_reference_id:attempt,
  metadata:{attempt_id:attempt}
 }}
};

async function handlerWith(rpc){
 const source=await readFile('supabase/functions/stripe-webhook/index.ts','utf8');
 const isolated=source.replace(/^import\s*\{[^}]+\}\s*from\s*'npm:@supabase\/supabase-js@2\.118\.0';\s*/m,'');
 let handler;
 const values={STRIPE_WEBHOOK_SECRET:secret,SUPABASE_URL:'https://example.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'test-service-role'};
 const context={
  Response,Request,TextEncoder,crypto:webcrypto,JSON,
  createClient:()=>({rpc}),
  Deno:{serve(fn){handler=fn;},env:{get(name){return values[name]??null;}}}
 };
 context.globalThis=context;
 runInNewContext(stripTypeScriptTypes(isolated),context);
 assert.equal(typeof handler,'function');
 return handler;
}

function requestFor(event,signatureValid=true){
 const raw=JSON.stringify(event),timestamp=Math.floor(Date.now()/1000);
 const signature=createHmac('sha256',signatureValid?secret:'wrong-secret')
  .update(timestamp+'.'+raw).digest('hex');
 return new Request('https://example.supabase.co/functions/v1/stripe-webhook',{
  method:'POST',headers:{'stripe-signature':`t=${timestamp},v1=${signature}`},body:raw
 });
}

test('signed async failure reaches the transactional reconciliation with the correct ledger identifiers',async()=>{
 const calls=[];
 const handler=await handlerWith(async(name,args)=>{calls.push({name,args});return {data:'failed',error:null};});
 const response=await handler(requestFor(original));
 assert.equal(response.status,200);
 assert.equal((await response.json()).result,'failed');
 assert.equal(calls.length,1);
 assert.equal(calls[0].name,'reconcile_signed_async_checkout_failure');
 assert.deepEqual({...calls[0].args},{
  p_event_id:original.id,p_stripe_account:original.account,
  p_session:original.data.object.id,p_intent:original.data.object.payment_intent,
  p_attempt:attempt,p_amount:250,p_currency:'eur'
 });
});

test('bad signature, live event, and inconsistent failure payload never reach the ledger',async()=>{
 let calls=0;
 const handler=await handlerWith(async()=>{calls++;return {data:'failed',error:null};});
 assert.equal((await handler(requestFor(original,false))).status,400);
 for(const change of [
  event=>{event.livemode=true;},
  event=>{event.data.object.metadata.attempt_id='90000000-0000-4000-8000-000000000002';},
  event=>{event.data.object.payment_status='paid';},
  event=>{event.data.object.amount_total=250.5;},
  event=>{event.data.object.currency='usd';},
  event=>{event.account='';},
  event=>{event.data.object.id='cs_live_NotAllowed';}
 ]){
  const event=structuredClone(original);change(event);
  assert.equal((await handler(requestFor(event))).status,400);
 }
 assert.equal(calls,0);
});

test('ledger failure returns a retryable non-2xx response',async()=>{
 const handler=await handlerWith(async()=>({data:null,error:{message:'database unavailable'}}));
 const response=await handler(requestFor(original));
 assert.equal(response.status,500);
 assert.match((await response.json()).error,/non riconciliato/);
});
