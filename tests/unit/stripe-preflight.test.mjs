import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';

for(const name of ['stripe-checkout-individual','stripe-checkout-group','stripe-full-refund']){
 test(name+' returns a valid bodyless CORS preflight for Supabase browser requests',async()=>{
  const source=await readFile('supabase/functions/'+name+'/index.ts','utf8');
  const isolated=source.replace(/^import\s*\{[^}]+\}\s*from\s*'npm:@supabase\/supabase-js@2\.118\.0';\s*/m,'');
  let handler;
  const context={
   Response,Request,URL,URLSearchParams,JSON,
   Deno:{serve(callback){handler=callback;},env:{get(){return null;}}},
   fetch(){throw Error('Network must not be called on OPTIONS');}
  };
  context.globalThis=context;
  runInNewContext(stripTypeScriptTypes(isolated),context);
  assert.equal(typeof handler,'function');
  const response=await handler(new Request('https://example.supabase.co/functions/v1/'+name,{
   method:'OPTIONS',headers:{
    Origin:'https://ambrogiocorti.github.io',
    'Access-Control-Request-Method':'POST',
    'Access-Control-Request-Headers':'authorization,x-client-info,apikey,content-type'
   }
  }));
  assert.equal(response.status,204);
  assert.equal(await response.text(),'');
  assert.equal(response.headers.get('access-control-allow-origin'),'https://ambrogiocorti.github.io');
  const allowed=(response.headers.get('access-control-allow-headers')||'')
   .toLowerCase().split(',').map(x=>x.trim());
  for(const key of ['authorization','x-client-info','apikey','content-type']){
   assert.ok(allowed.includes(key),'CORS missing '+key);
  }
 });
}
