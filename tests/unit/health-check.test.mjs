import test from 'node:test';
import assert from 'node:assert/strict';
import {checkPages} from '../../scripts/health-check.mjs';

function fakeFetch({status=200,start='/BreakApp/',badWorker=false}={}){
  return async url=>{
    const path=new URL(url).pathname;
    if(path.endsWith('manifest.webmanifest')){
      return new Response(JSON.stringify({name:'BreakApp',display:'standalone',
        start_url:start,scope:start}),{status});
    }
    if(path.endsWith('sw.js'))
      return new Response(badWorker?'not a worker':"self.addEventListener('push',()=>{});",{status});
    return new Response('<html><title>BreakApp — Accedi</title><form id="auth-form"></form></html>',{status});
  };
}
test('public Pages probe validates login, manifest scope and Service Worker',async()=>{
  const result=await checkPages({fetchImpl:fakeFetch()});
  assert.equal(result.ok,true);
  assert.equal(result.verified.length,3);
});
test('public Pages probe rejects wrong PWA scope',async()=>{
  await assert.rejects(checkPages({fetchImpl:fakeFetch({start:'/'})}),/wrong location/);
});
test('public Pages probe rejects a missing service worker',async()=>{
  await assert.rejects(checkPages({fetchImpl:fakeFetch({badWorker:true})}),/not a JavaScript worker/);
});
test('public Pages probe rejects an unavailable site',async()=>{
  await assert.rejects(checkPages({fetchImpl:fakeFetch({status:503})}),/HTTP 503/);
});
test('public Pages probe rejects insecure URLs',async()=>{
  await assert.rejects(checkPages({siteUrl:'http://example.com/BreakApp/',
    fetchImpl:fakeFetch()}),/HTTPS/);
});
