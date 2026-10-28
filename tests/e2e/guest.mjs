import {chromium,firefox,webkit} from 'playwright';
import {spawn} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
import assert from 'node:assert/strict';
const origin='http://127.0.0.1:5177';
const fixture=`<!doctype html><html lang="it"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/src/css/base.css"></head><body><main class="container"><article class="auth-card"><div id="signed-out-view"></div><div id="signed-in-view" hidden></div></article></main>
<script type="module">
import {initializeGuestAccess} from '/src/js/features/auth/guest.js';
const guest={id:'guest-original',email:'hidden@guest.breakapp.invalid',email_confirmed_at:new Date().toISOString(),app_metadata:{guest:true}},proof={id:'email-identity',email:'me@test.invalid',email_confirmed_at:new Date().toISOString(),app_metadata:{}};
window.fixture={calls:[],confirmed:false};let changed;
const emit=user=>{document.getElementById('signed-in-view').hidden=!user;document.getElementById('signed-out-view').hidden=Boolean(user);changed?.('SIGNED_IN',user?{user}:null)};
const client={auth:{onAuthStateChange(fn){changed=fn;queueMicrotask(()=>emit(null))},async setSession(data){window.fixture.calls.push({name:'setSession',data});emit(guest);return{data:{user:guest}}},async signInWithOtp(args){window.fixture.calls.push({name:'sendEmail',args});return{data:{}}}},
async rpc(name){return{data:name==='my_guest_email_recovery_status'?window.fixture.confirmed:null}},
functions:{async invoke(name,{body}){window.fixture.calls.push({name:body.action,body});
 if(body.action==='prepare_recovery')return{data:{request_id:'request-1'}};
 if(body.action==='list_recovery')return{data:window.fixture.confirmed?{pending:[],linked:[{id:guest.id,name:'Test Guest',school:'Scuola'}]}:{pending:[{id:'request-1',name:'Test Guest',school:'Scuola'}],linked:[]}};
 if(body.action==='confirm_recovery')window.fixture.confirmed=true;
 return{data:{access_token:'fixture-guest-token',refresh_token:'fixture-refresh',private_token:(body.action==='create'?'a':body.action==='confirm_recovery'?'b':'c').repeat(64)}};}},
from(name){let filters=[];const q={select(){return this},eq(k,v){filters.push([k,v]);return this},order(){return this},then(resolve,reject){const rows=name==='schools'?[{id:'school',name:'Scuola',is_active:true,require_guest_class:true}]:[{name:'5A',school_id:'school',active:true}];return Promise.resolve({data:rows.filter(r=>filters.every(([k,v])=>r[k]===v))}).then(resolve,reject)}};return q}};
initializeGuestAccess(client);window.fixture.asEmail=()=>emit(proof);window.fixture.ready=true;
</script></body></html>`;
const server=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','5177','--strictPort'],{stdio:'ignore',env:{...process.env,GITHUB_PAGES_BASE:'/'}});let browser;
try{
 for(let i=0;i<50;i++){try{if((await fetch(origin)).ok)break;}catch{}await delay(200);}
 for(const[name,engine]of Object.entries({chromium,firefox,webkit})){
  browser=await engine.launch({headless:true});
  for(const viewport of[{width:1440,height:900},{width:390,height:844}]){
   const page=await browser.newPage({viewport}),errors=[];page.on('pageerror',e=>errors.push(e.message));
   await page.route(origin+'/fixture',r=>r.fulfill({contentType:'text/html',body:fixture}));await page.goto(origin+'/fixture');await page.waitForFunction(()=>window.fixture?.ready);
   await page.getByLabel('Nome e cognome',{exact:true}).fill('Test Guest');await page.getByLabel('Classe della scuola',{exact:true}).fill('5A');
   await page.getByRole('button',{name:'Accedi come ospite',exact:true}).click();
   await page.getByLabel('Link privato personale').waitFor();
   await page.getByLabel('Email di recupero dell’ospite',{exact:true}).fill('me@test.invalid');await page.getByRole('button',{name:'Verifica email di recupero',exact:true}).click();
   await page.waitForFunction(()=>window.fixture.calls.some(c=>c.name==='sendEmail'&&c.args.options.shouldCreateUser===true));
   await page.evaluate(()=>window.fixture.asEmail());await page.locator('summary').click();await page.getByRole('button',{name:'Verifica o recupera accesso ospite',exact:true}).click();
   await page.getByRole('button',{name:'Conferma collegamento: Test Guest · Scuola',exact:true}).click();
   await page.waitForFunction(()=>document.querySelector('[aria-label="Link privato personale"]')?.value.endsWith('#guest='+'b'.repeat(64)));
   await page.evaluate(()=>window.fixture.asEmail());await page.getByRole('button',{name:'Verifica o recupera accesso ospite',exact:true}).click();
   await page.getByRole('button',{name:'Riprendi ospite: Test Guest · Scuola',exact:true}).click();
   await page.waitForFunction(()=>document.querySelector('[aria-label="Link privato personale"]')?.value.endsWith('#guest='+'c'.repeat(64)));
   const privateLink=await page.getByLabel('Link privato personale').evaluate(n=>n.value);assert.ok(privateLink.endsWith('#guest='+ 'c'.repeat(64)));
   const width=await page.evaluate(()=>({scroll:document.documentElement.scrollWidth,viewport:innerWidth}));assert.ok(width.scroll<=width.viewport+3);assert.deepEqual(errors,[]);
   console.log(JSON.stringify({browser:name,viewport,result:'PASS',scenario:'guest, school-required class, verified email binding, original identity recovery'}));await page.close();
  }await browser.close();browser=null;
 }
}finally{await browser?.close();server.kill('SIGTERM');}
