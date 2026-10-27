// Browser tests of the actual ES module with a controlled API fixture.
// Tenant and permission checks are covered separately by notification-preferences.sql.
import {chromium,firefox,webkit} from 'playwright';
import {readFileSync} from 'node:fs';
import {spawn} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
import assert from 'node:assert/strict';

const site='http://127.0.0.1:5174';
const markup=readFileSync('index.html','utf8').match(/<dialog id="notifications-dialog"[\s\S]*?<\/dialog>/)?.[0];
assert.ok(markup);
const fixture=`<!doctype html><html lang="it"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/src/css/base.css"></head><body>
<button id="notifications-toggle" hidden>Notifiche <span id="notifications-unread" hidden></span></button>${markup}
<script type="module">
import {initializeInAppNotifications} from '/src/js/features/notifications/notifications.js';
const state=window.fixture={prefs:{browser_alerts:true,push_orders:true,push_groups:true,push_support:true,push_announcements:true},
 calls:[],saves:0,unsubscribed:0,disabled:0,notices:[{id:'notice-1',message:'Ordine di prova pronto',created_at:new Date().toISOString(),read_at:null}]};
const channel={on(){return this},subscribe(){return this}};
Object.defineProperty(navigator,'serviceWorker',{value:{getRegistration:async()=>({pushManager:{getSubscription:async()=>({
 endpoint:'https://fcm.googleapis.com/fcm/send/browser_preference_test',unsubscribe:async()=>{state.unsubscribed++;return true}
})}})}});
const client={auth:{onAuthStateChange(fn){state.authChanged=fn},async getUser(){return{data:{user:{id:'fixture-user'}}}}},
 channel(){return channel},removeChannel(){},
 async rpc(name,args){
  state.calls.push({name,args});
  if(name==='get_my_notification_preferences')return{data:{...state.prefs}};
  if(name==='set_my_notification_preferences'){
   if(state.failSave)return{error:{message:'Salvataggio di prova rifiutato'}};
   for(const[key,value]of Object.entries(args))state.prefs[key.slice(2)]=value;
   state.saves++;return{data:{...state.prefs}};
  }
  if(name==='disable_my_push_subscription'){state.disabled++;return{data:true}};
  throw new Error('Unexpected RPC '+name);
 },
 from(name){if(name!=='customer_notifications')throw new Error('Unexpected table '+name);
  const q={select(){return this},eq(){return this},order(){return this},limit(){return this},
   update(patch){this.patch=patch;return this},then(resolve,reject){
    if(this.patch)state.notices=state.notices.map(n=>({...n,...this.patch}));
    return Promise.resolve({data:state.notices.map(n=>({...n}))}).then(resolve,reject)
   }};return q;
 }};
initializeInAppNotifications(client);
</script></body></html>`;
const server=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','5174','--strictPort'],
 {stdio:'ignore',env:{...process.env,GITHUB_PAGES_BASE:'/'}});
let browser;
try{
 let available=false;
 for(let attempt=0;attempt<50;attempt++){
  try{available=(await fetch(site)).ok;}catch{}
  if(available)break;
  await delay(200);
 }
 assert.ok(available,'Notification test server did not start');
 for(const[name,engine]of Object.entries({chromium,firefox,webkit})){
  browser=await engine.launch({headless:true});
  for(const viewport of [{width:1440,height:900},{width:390,height:844}]){
   const page=await browser.newPage({viewport});
   const errors=[];page.on('pageerror',error=>errors.push(error.message));
   await page.route(site+'/__notification_fixture',route=>route.fulfill({contentType:'text/html',body:fixture}));
   await page.goto(site+'/__notification_fixture');
   await page.locator('#notifications-toggle').waitFor({state:'visible'});
   await page.locator('#notifications-toggle').click();
   await page.waitForFunction(()=>window.fixture.calls.some(x=>x.name==='get_my_notification_preferences'));
   assert.equal(await page.locator('#notice-push-groups').isChecked(),true);
   await page.locator('#notice-push-groups').uncheck();
   await page.locator('#notice-push-announcements').uncheck();
   await page.locator('#notification-preferences-form button[type="submit"]').click();
   await page.waitForFunction(()=>window.fixture.saves===1);
   assert.equal(await page.evaluate(()=>window.fixture.prefs.push_groups),false);
   assert.equal(await page.evaluate(()=>window.fixture.prefs.push_orders),true);
   assert.equal(await page.locator('#notifications-list article').count(),1,'Opt-out must preserve in-app notices');
   await page.evaluate(()=>{window.fixture.failSave=true;});
   await page.locator('#notice-push-orders').uncheck();
   await page.locator('#notification-preferences-form button[type="submit"]').click();
   await page.waitForFunction(()=>document.querySelector('#notifications-feedback').textContent.includes('rifiutato'));
   assert.equal(await page.evaluate(()=>window.fixture.prefs.push_orders),true,'Failed write changed stored preference');
   await page.locator('#notifications-refresh').click();
   await page.waitForFunction(()=>document.querySelector('#notice-push-orders').checked);
   await page.locator('#notifications-push-disable').click();
   await page.waitForFunction(()=>window.fixture.unsubscribed===1&&window.fixture.disabled===1);
   await page.getByRole('button',{name:'Segna come letta'}).click();
   await page.waitForFunction(()=>document.querySelector('#notifications-unread').hidden);
   const size=await page.locator('#notifications-dialog').evaluate(node=>({width:node.scrollWidth,client:node.clientWidth}));
   assert.ok(size.width<=size.client+2,'Notification dialog has horizontal overflow');
   await page.evaluate(()=>window.fixture.authChanged('SIGNED_OUT',null));
   await page.waitForFunction(()=>!document.querySelector('#notifications-dialog').open);
   assert.deepEqual(errors,[]);
   console.log(JSON.stringify({browser:name,viewport,result:'PASS',scenario:'notification preferences, API rejection, revocation, read status, logout'}));
   await page.close();
  }
  await browser.close();browser=null;
 }
}finally{await browser?.close();server.kill('SIGTERM');}
