import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {resolveAllowedSite,corsHeaders} from '../../supabase/functions/_shared/allowed-sites.mjs';

const uuid='00000000-0000-4000-8000-000000000001';
for(const kind of ['individual','group']){
 test(kind+' checkout uses only the server-configured return URL for the caller origin',async()=>{
  const file='supabase/functions/stripe-checkout-'+kind+'/index.ts';
  const src=(await readFile(file,'utf8'))
   .replace(/^import\s*\{[^}]+\}\s*from\s*'npm:@supabase\/supabase-js@2\.118\.0';\s*/m,'const createClient=globalThis.__createClient;')
   .replace("import {resolveAllowedSite,corsHeaders} from '../_shared/allowed-sites.mjs';",'const {resolveAllowedSite,corsHeaders}=globalThis.__siteHelpers;');
  const outbound=[];let handler;
  const env={SUPABASE_URL:'https://db.example',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service',STRIPE_SECRET_KEY:'sk_test_SAFE',
   BREAKAPP_ALLOWED_SITE_URLS:'https://ambrogiocorti.github.io/BreakApp/,https://demo.example/preview/'};
  const context={Request,Response,URL,URLSearchParams,JSON,Number,
   __siteHelpers:{resolveAllowedSite,corsHeaders},
   Deno:{serve(fn){handler=fn},env:{get(k){return env[k]}}},
   __createClient:()=>({auth:{getUser:async()=>({data:{user:{id:'user'}},error:null})},
    rpc:async(name)=>name.startsWith('begin_')?{data:{attempt_id:uuid,stripe_account_id:'acct_Test1',amount_cents:250},error:null}:{data:null,error:null}}),
   fetch:async(url,options)=>{outbound.push({url,options});return new Response(JSON.stringify({id:'cs_test_Safe',url:'https://checkout.stripe.com/c/pay/safe'}),{status:200})}
  };
  context.globalThis=context;runInNewContext(stripTypeScriptTypes(src),context);
  const payload=kind==='individual'?{order_id:uuid,request_key:uuid}:{group_id:uuid,request_key:uuid,line_ids:[uuid]};
  const invoke=origin=>handler(new Request('https://db.example/functions/v1/checkout',{
   method:'POST',headers:{Origin:origin,Authorization:'Bearer test','content-type':'application/json'},body:JSON.stringify(payload)
  }));
  const good=await invoke('https://demo.example');
  assert.equal(good.status,200);
  assert.equal(good.headers.get('access-control-allow-origin'),'https://demo.example');
  const form=new URLSearchParams(outbound[0].options.body);
  const route=kind==='individual'?'orders':'groups';
  assert.equal(form.get('success_url'),'https://demo.example/preview/#'+route);
  assert.equal(form.get('cancel_url'),'https://demo.example/preview/#'+route);
  assert.equal(outbound[0].options.headers['Stripe-Account'],'acct_Test1');
  const bad=await invoke('https://demo.example.attacker.test');
  assert.equal(bad.status,403);
  assert.equal(bad.headers.get('access-control-allow-origin'),null);
  assert.equal(outbound.length,1);
 });
}
