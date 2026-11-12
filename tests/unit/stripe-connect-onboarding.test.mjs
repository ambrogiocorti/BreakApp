import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {resolveAllowedSite,corsHeaders} from '../../supabase/functions/_shared/allowed-sites.mjs';

const origin='https://ambrogiocorti.github.io';
const schoolA='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const schoolB='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const schoolC='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const source=await readFile('supabase/functions/stripe-connect-onboarding/index.ts','utf8');
const isolated=source.replace(
 "import { createClient } from 'npm:@supabase/supabase-js@2.118.0';",
 'const createClient = globalThis.__createClient;'
).replace("import {resolveAllowedSite,corsHeaders} from '../_shared/allowed-sites.mjs';",
 'const {resolveAllowedSite,corsHeaders}=globalThis.__siteHelpers;');
const compiled=stripTypeScriptTypes(isolated);

function harness({authenticated=true,admin=true,key='rk_test_TESTONLY',serviceKey='service-test',
  stripeStatus=200,stripeCode='resource_missing',stripeUrl='https://connect.stripe.com/setup/s/test-only',
  sites='',dbError=false,merchants={[schoolA]:'acct_TESTA',[schoolB]:'acct_TESTB'}}={}){
 let handler;const outbound=[],queries=[];
 const env={SUPABASE_URL:'https://example.supabase.co',SUPABASE_ANON_KEY:'public-test-only',
  SUPABASE_SERVICE_ROLE_KEY:serviceKey,STRIPE_ONBOARDING_KEY:key,BREAKAPP_ALLOWED_SITE_URLS:sites};
 const context={
  Response,URL,URLSearchParams,JSON,console:{error(){}},
  __siteHelpers:{resolveAllowedSite,corsHeaders},
  Deno:{env:{get:name=>env[name]},serve:callback=>{handler=callback}},
  __createClient:(_url,providedKey)=>{
   if(providedKey===serviceKey)return{from(table){
    assert.equal(table,'school_stripe_merchants');let requestedSchool;
    return{select(fields){assert.equal(fields,'stripe_account_id');return this},
     eq(field,value){assert.equal(field,'school_id');requestedSchool=value;queries.push(value);return this},
     async maybeSingle(){return dbError?{data:null,error:new Error('DB unavailable')}:
      {data:merchants[requestedSchool]?{stripe_account_id:merchants[requestedSchool]}:null,error:null}}
    };
   }};
   return{
    auth:{getUser:async()=>authenticated?{data:{user:{id:'user-1'}},error:null}:{data:{},error:new Error('not authenticated')}},
    rpc:async name=>{assert.equal(name,'is_current_platform_admin');return{data:admin,error:null}}
   };
  },
  fetch:async(url,options)=>{
   outbound.push({url,options});
   return new Response(JSON.stringify(stripeStatus===200?{url:stripeUrl}:
    {error:{type:'invalid_request_error',code:stripeCode,message:'SENSITIVE NEVER DISPLAY'}}),{
    status:stripeStatus,headers:{'Content-Type':'application/json','request-id':'req_TESTONLY123456'}});
  }
 };
 context.globalThis=context;runInNewContext(compiled,context);
 return{outbound,queries,
  preflight:(requestOrigin=origin)=>handler(new Request('https://example.supabase.co/functions/v1/stripe-connect-onboarding',{
   method:'OPTIONS',headers:{Origin:requestOrigin,'Access-Control-Request-Method':'POST',
    'Access-Control-Request-Headers':'authorization, x-client-info, apikey, content-type'}})),
  invoke:(body={school_id:schoolA},authorization='Bearer token',requestOrigin=origin)=>handler(
   new Request('https://example.supabase.co/functions/v1/stripe-connect-onboarding',{
    method:'POST',headers:{Authorization:authorization,Origin:requestOrigin,'Content-Type':'application/json'},
    body:typeof body==='string'?body:JSON.stringify(body)}))
 };
}

test('preflight only allows configured origins and Supabase headers',async()=>{
 const h=harness(),r=await h.preflight();assert.equal(r.status,204);
 assert.equal(r.headers.get('access-control-allow-origin'),origin);
 assert.equal(r.headers.get('access-control-allow-methods'),'POST, OPTIONS');
 for(const header of ['authorization','x-client-info','apikey','content-type'])
  assert.ok(r.headers.get('access-control-allow-headers').split(',').map(x=>x.trim()).includes(header));
 const foreign=await h.preflight('https://attacker.example');assert.equal(foreign.status,403);
 assert.equal(foreign.headers.get('access-control-allow-origin'),null);assert.equal(h.outbound.length,0);
});

test('rejects foreign origins, invalid sessions and non-admin sessions before looking up a merchant',async()=>{
 const foreign=harness();assert.equal((await foreign.invoke({school_id:schoolA},'Bearer token','https://attacker.example')).status,403);
 const missing=harness();assert.equal((await missing.invoke({school_id:schoolA},'')).status,401);
 const invalid=harness({authenticated:false});assert.equal((await invalid.invoke()).status,401);
 const nonAdmin=harness({admin:false});assert.equal((await nonAdmin.invoke()).status,403);
 for(const h of [foreign,missing,invalid,nonAdmin]){assert.equal(h.outbound.length,0);assert.equal(h.queries.length,0)}
});

test('never accepts a merchant account or malformed school identifier from the browser',async()=>{
 for(const body of [{},null,[],{school_id:'invalid'},{school_id:schoolA,account_id:'acct_EVIL'},'not-json']){
  const h=harness();assert.equal((await h.invoke(body)).status,400);assert.equal(h.queries.length,0);assert.equal(h.outbound.length,0);
 }
 const h=harness();assert.equal((await h.invoke(' '.repeat(4097))).status,413);assert.equal(h.queries.length,0);
});

test('resolves the selected school account server-side, without creating or changing an association',async()=>{
 for(const [school,expected] of [[schoolA,'acct_TESTA'],[schoolB,'acct_TESTB']]){
  const h=harness(),r=await h.invoke({school_id:school});assert.equal(r.status,200);
  const data=await r.json();assert.equal(data.account_id,expected);assert.ok(data.onboarding_url.startsWith('https://connect.stripe.com/'));
  assert.deepEqual(h.queries,[school]);assert.equal(h.outbound.length,1);
  const req=h.outbound[0];assert.equal(req.url,'https://api.stripe.com/v1/account_links');
  assert.equal(req.options.headers['Stripe-Version'],'2026-09-30.endive');
  assert.equal(req.options.headers['Stripe-Account'],undefined);
  const fields=new URLSearchParams(req.options.body);
  assert.equal(fields.get('account'),expected);assert.equal(fields.get('type'),'account_onboarding');
  assert.equal(fields.get('return_url'),origin+'/BreakApp/#platform-configuration');
  assert.equal(fields.get('refresh_url'),origin+'/BreakApp/#platform-configuration');
 }
});

test('unbound schools and unavailable database fail closed without contacting Stripe',async()=>{
 const unbound=harness();assert.equal((await unbound.invoke({school_id:schoolC})).status,409);assert.equal(unbound.outbound.length,0);
 const unavailable=harness({dbError:true});assert.equal((await unavailable.invoke()).status,503);assert.equal(unavailable.outbound.length,0);
 const noService=harness({serviceKey:''});assert.equal((await noService.invoke()).status,503);assert.equal(noService.outbound.length,0);
});

test('only restricted test keys may be used and redirect URLs follow the configured site',async()=>{
 for(const key of ['rk_live_123456','sk_test_123456','']){
  const h=harness({key});assert.equal((await h.invoke()).status,503);assert.equal(h.outbound.length,0);
 }
 const h=harness({sites:origin+'/BreakApp/,https://demo.example/preview/'});
 const r=await h.invoke({school_id:schoolB},'Bearer token','https://demo.example');
 assert.equal(r.status,200);assert.equal(r.headers.get('access-control-allow-origin'),'https://demo.example');
 const fields=new URLSearchParams(h.outbound[0].options.body);
 assert.equal(fields.get('return_url'),'https://demo.example/preview/#platform-configuration');
 assert.equal(fields.get('refresh_url'),'https://demo.example/preview/#platform-configuration');
});

test('sanitizes Stripe errors and refuses non-Stripe destinations',async()=>{
 const h=harness({stripeStatus:404}),r=await h.invoke();assert.equal(r.status,502);
 const body=await r.json();assert.equal(body.stripe_code,'resource_missing');
 assert.equal(body.stripe_request_id,'req_TESTONLY123456');assert.match(body.error,/merchant associato/i);
 assert.ok(!JSON.stringify(body).includes('SENSITIVE'));
 const denied=harness({stripeStatus:403,stripeCode:'permission_denied'});
 assert.match((await (await denied.invoke()).json()).error,/permessi Account Links/);
 const forged=harness({stripeUrl:'https://stripe.com.attacker.example/setup'});
 assert.equal((await forged.invoke()).status,502);
});
