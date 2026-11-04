import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac,webcrypto} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
import {runInNewContext} from 'node:vm';

const secret='whsec_test_unit_only';
const token='test-dispatch-token-at-least-32-characters';
const refundId='94000000-0000-4000-8000-000000000001';
const leaseId='94000000-0000-4000-8000-000000000002';
const event={id:'evt_RefundTest1',livemode:false,type:'refund.updated',account:'acct_TestSchool',data:{object:{
 id:'re_RefundTest1',object:'refund',status:'succeeded',payment_intent:'pi_PaymentTest1',
 amount:250,currency:'eur',metadata:{breakapp_refund_id:refundId}
}}};

async function makeHandler(path,{rpc,fetchImpl}={}){
 const source=await readFile(path,'utf8');
 const isolated=source.replace(/^import\s*\{[^}]+\}\s*from\s*'npm:@supabase\/supabase-js@2\.118\.0';\s*/m,'');
 let handler;
 const values={STRIPE_WEBHOOK_SECRET:secret,SUPABASE_URL:'https://example.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY:'test-service-role',STRIPE_SECRET_KEY:'sk_test_abc123',PUSH_DISPATCH_TOKEN:token};
 const context={Response,Request,TextEncoder,URLSearchParams,AbortSignal,crypto:webcrypto,JSON,
  createClient:()=>({rpc}),fetch:fetchImpl,
  Deno:{serve(fn){handler=fn;},env:{get(name){return values[name]??null;}}}};
 context.globalThis=context;
 runInNewContext(stripTypeScriptTypes(isolated),context);
 assert.equal(typeof handler,'function');
 return handler;
}
function signedRequest(value,valid=true){
 const raw=JSON.stringify(value),timestamp=Math.floor(Date.now()/1000);
 const signature=createHmac('sha256',valid?secret:'wrong-secret').update(timestamp+'.'+raw).digest('hex');
 return new Request('https://example.supabase.co/functions/v1/stripe-webhook',{
  method:'POST',headers:{'stripe-signature':`t=${timestamp},v1=${signature}`},body:raw});
}
function dispatchRequest(){return new Request('https://example.supabase.co/functions/v1/group-refund-dispatch',{
 method:'POST',headers:{'x-breakapp-dispatch-token':token}});}
const job={refund_id:refundId,lease_token:leaseId,claim_revision:4,account:'acct_TestSchool',
 provider_refund:'re_RefundTest1',payment_intent:'pi_PaymentTest1',amount_cents:250};
const providerRefund={id:job.provider_refund,object:'refund',livemode:false,
 payment_intent:job.payment_intent,amount:250,currency:'eur',status:'failed',
 metadata:{breakapp_refund_id:refundId}};

test('signed pending, successful and failed refund events are durably queued, not finalized from snapshots',async()=>{
 const calls=[];
 const handler=await makeHandler('supabase/functions/stripe-webhook/index.ts',{
  rpc:async(name,args)=>{calls.push({name,args});return {data:'queued',error:null};}});
 for(const [type,status] of [['refund.created','pending'],['refund.updated','succeeded'],['refund.failed','failed']]){
  const input=structuredClone(event);input.type=type;input.data.object.status=status;
  const response=await handler(signedRequest(input));
  assert.equal(response.status,200);
  assert.equal((await response.json()).result,'queued');
 }
 assert.equal(calls.length,3);
 assert.equal(calls.every(x=>x.name==='enqueue_signed_refund_observation'),true);
 assert.equal(calls[2].args.p_snapshot_status,'failed');
 assert.equal(calls[2].args.p_refund,refundId);
});

test('refund event with invalid signature, identity, status or currency is rejected before queueing',async()=>{
 let calls=0;
 const handler=await makeHandler('supabase/functions/stripe-webhook/index.ts',{
  rpc:async()=>{calls++;return {data:'queued',error:null};}});
 assert.equal((await handler(signedRequest(event,false))).status,400);
 for(const change of [
  x=>{x.livemode=true;},x=>{x.data.object.metadata.breakapp_refund_id='not-a-uuid';},
  x=>{x.data.object.amount=0;},x=>{x.data.object.currency='usd';},
  x=>{x.type='refund.failed';x.data.object.status='succeeded';},x=>{x.account='';}
 ]){const input=structuredClone(event);change(input);assert.equal((await handler(signedRequest(input))).status,400);}
 assert.equal(calls,0);
});

test('webhook returns non-2xx when durable enqueue fails',async()=>{
 const handler=await makeHandler('supabase/functions/stripe-webhook/index.ts',{
  rpc:async()=>({data:null,error:{message:'unavailable'}})});
 assert.equal((await handler(signedRequest(event))).status,500);
});

test('dispatcher looks up the current refund in its connected account before finalizing',async()=>{
 const calls=[],requests=[];
 const rpc=async(name,args)=>{
  calls.push({name,args});
  if(name==='push_runtime_configuration')return {data:{breakapp_dispatch_token:token},error:null};
  if(name==='claim_refund_dispatch')return {data:[],error:null};
  if(name==='claim_refund_observations')return {data:[job],error:null};
  if(name==='finish_refund_observation')return {data:'failed',error:null};
  throw Error('Unexpected RPC '+name);
 };
 const handler=await makeHandler('supabase/functions/group-refund-dispatch/index.ts',{
  rpc,fetchImpl:async(url,init)=>{requests.push({url,init});return new Response(JSON.stringify(providerRefund),{status:200});}});
 const response=await handler(dispatchRequest());
 assert.equal(response.status,200);
 assert.equal((await response.json()).reconciled,1);
 assert.equal(requests.length,1);
 assert.equal(requests[0].init.method,'GET');
 assert.equal(requests[0].init.headers['Stripe-Account'],job.account);
 const finish=calls.find(x=>x.name==='finish_refund_observation');
 assert.equal(finish.args.p_provider_status,'failed');
 assert.equal(finish.args.p_revision,4);
 assert.equal(finish.args.p_token,leaseId);
 assert.equal(calls.some(x=>x.name==='fail_refund_observation'),false);
});

test('unexpected or unavailable provider response is retried without finalizing the ledger',async()=>{
 for(const fetchImpl of [
  async()=>new Response(JSON.stringify({...providerRefund,amount:251}),{status:200}),
  async()=>new Response('',{status:503}),
  async()=>{throw Error('offline');}
 ]){
  const calls=[];
  const rpc=async(name,args)=>{
   calls.push({name,args});
   if(name==='push_runtime_configuration')return {data:{breakapp_dispatch_token:token},error:null};
   if(name==='claim_refund_dispatch')return {data:[],error:null};
   if(name==='claim_refund_observations')return {data:[job],error:null};
   if(name==='fail_refund_observation')return {data:null,error:null};
   throw Error('Unexpected RPC '+name);
  };
  const handler=await makeHandler('supabase/functions/group-refund-dispatch/index.ts',{rpc,fetchImpl});
  const response=await handler(dispatchRequest());
  assert.equal(response.status,200);
  assert.equal((await response.json()).observation_errors,1);
  assert.equal(calls.some(x=>x.name==='finish_refund_observation'),false);
  assert.equal(calls.filter(x=>x.name==='fail_refund_observation').length,1);
 }
});
