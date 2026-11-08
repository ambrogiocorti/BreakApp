import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac,webcrypto} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
import {runInNewContext} from 'node:vm';

const secret='whsec_test_unit_only';
async function makeHandler(rpc){
 const source=await readFile(new URL('../../supabase/functions/stripe-webhook/index.ts',import.meta.url),'utf8');
 const isolated=source.replace(/^import\s*\{[^}]+\}\s*from\s*'npm:@supabase\/supabase-js@2\.118\.0';\s*/m,'');
 let handler;
 const values={STRIPE_WEBHOOK_SECRET:secret,SUPABASE_URL:'https://example.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'test-service-role'};
 const context={Response,Request,TextEncoder,JSON,crypto:webcrypto,createClient:()=>({rpc}),
  Deno:{serve(fn){handler=fn;},env:{get(name){return values[name]??null;}}}};
 context.globalThis=context;
 runInNewContext(stripTypeScriptTypes(isolated),context);
 return handler;
}
function signed(value,key=secret){
 const raw=JSON.stringify(value),t=Math.floor(Date.now()/1000);
 const v1=createHmac('sha256',key).update(t+'.'+raw).digest('hex');
 return new Request('https://example.supabase.co/functions/v1/stripe-webhook',{method:'POST',
  headers:{'stripe-signature':`t=${t},v1=${v1}`},body:raw});
}
const event=(object={})=>({id:'evt_AccountTest1',livemode:false,type:'account.updated',
 account:'acct_DemoSchool',created:1794000000,data:{object:{id:'acct_DemoSchool',object:'account',
 charges_enabled:true,payouts_enabled:true,details_submitted:true,...object}}});

test('signed account.updated forwards only the verified status flags',async()=>{
 const calls=[];
 const handler=await makeHandler(async(name,args)=>{calls.push([name,args]);return{data:'applied',error:null};});
 const response=await handler(signed(event()));
 assert.equal(response.status,200);
 assert.deepEqual(JSON.parse(JSON.stringify(calls)),[['apply_signed_stripe_account_status',{p_event:'evt_AccountTest1',
  p_account:'acct_DemoSchool',p_created:1794000000,p_charges:true,p_payouts:true,p_details:true}]]);
});

test('an account event for a different account than the object is rejected',async()=>{
 let called=false;
 const handler=await makeHandler(async()=>{called=true;return{data:null,error:null};});
 const response=await handler(signed(event({id:'acct_Other'})));
 assert.equal(response.status,400);assert.equal(called,false);
});

test('an unsigned account event never reaches the database',async()=>{
 let called=false;
 const handler=await makeHandler(async()=>{called=true;return{data:null,error:null};});
 const response=await handler(signed(event(),'whsec_wrong'));
 assert.equal(response.status,400);assert.equal(called,false);
});

test('a database failure is not acknowledged so Stripe retries',async()=>{
 const handler=await makeHandler(async()=>({data:null,error:{message:'down'}}));
 assert.equal((await handler(signed(event()))).status,500);
});

test('the status RPC is reserved to the service role and never creates associations',async()=>{
 const sql=await readFile(new URL('../../supabase/migrations/20261108223000_stripe_account_status_sync.sql',import.meta.url),'utf8');
 assert.match(sql,/revoke all on function public\.apply_signed_stripe_account_status[\s\S]*from public,anon,authenticated/);
 assert.match(sql,/grant execute on function public\.apply_signed_stripe_account_status[\s\S]*to service_role/);
 assert.doesNotMatch(sql,/insert into public\.school_stripe_merchants/);
});
