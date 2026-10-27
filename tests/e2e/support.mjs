import {chromium,firefox,webkit} from 'playwright';
import {spawn} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';
import assert from 'node:assert/strict';
const origin='http://127.0.0.1:5176';
let fixture=readFileSync('index.html','utf8').replace(/<script[\s\S]*?<\/script>/gi,'').replace('</head>','<link rel="stylesheet" href="/src/css/base.css"></head>');
fixture=fixture.replace('</body>',`<script type="module">
import {initializeSupportCenter} from '/src/js/features/support/support.js';
const user={id:'member'},tickets=[],messages=[];window.fixture={calls:[]};
const groups=[{id:'group-1',school_id:'school-1',title:'Gruppo intervallo',lines:[{id:'own-line',quantity:1,name:'Panino'}],payments:[{id:'own-payment',amount_cents:250,status:'succeeded'}]}];
const client={auth:{onAuthStateChange(){},async getUser(){return{data:{user}}},mfa:{async getAuthenticatorAssuranceLevel(){return{data:{currentLevel:'aal1'}}}}},
from(name){let filters=[],only=false;const q={select(){return this},eq(k,v){filters.push([k,v]);return this},order(){return this},limit(){return this},in(){return this},single(){only=true;return this},
then(resolve,reject){let data=name==='schools'?[{id:'school-1',name:'Scuola',is_active:true}]:name==='support_tickets'?tickets:name==='support_messages'?messages:[];
 data=data.filter(row=>filters.every(([k,v])=>row[k]===v));return Promise.resolve({data:only?data[0]:data}).then(resolve,reject)}};return q},
async rpc(name,args){window.fixture.calls.push({name,args});
 if(name==='my_support_group_references')return{data:groups};
 if(name==='open_group_support_ticket'){const id='ticket-'+tickets.length;tickets.push({id,school_id:'school-1',group_id:args.p_group,visibility:args.p_visibility,owner_id:'member',subject:args.p_subject,status:'open',updated_at:new Date().toISOString()});messages.push({id:'message-'+messages.length,ticket_id:id,author_id:'member',body:args.p_message,created_at:new Date().toISOString()});return{data:id}};
 if(name==='post_support_message'){messages.push({id:'reply',ticket_id:args.p_ticket_id,author_id:'member',body:args.p_body,created_at:new Date().toISOString()});return{data:'reply'}};
 return{data:null};}};
initializeSupportCenter(client);window.fixture.ready=true;
</script></body>`);
const server=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','5176','--strictPort'],{stdio:'ignore',env:{...process.env,GITHUB_PAGES_BASE:'/'}});let browser;
try{
 for(let i=0;i<50;i++){try{if((await fetch(origin)).ok)break;}catch{}await delay(200);}
 for(const[name,engine]of Object.entries({chromium,firefox,webkit})){
  browser=await engine.launch({headless:true});
  for(const viewport of[{width:1440,height:900},{width:390,height:844}]){
   const page=await browser.newPage({viewport}),errors=[];page.on('pageerror',e=>errors.push(e.message));
   await page.route(origin+'/fixture',r=>r.fulfill({contentType:'text/html',body:fixture}));await page.goto(origin+'/fixture');
   await page.waitForFunction(()=>window.fixture?.ready);await page.locator('#support-group-reference').selectOption('group-1');
   assert.equal(await page.locator('#support-group-line').isDisabled(),true);
   await page.locator('#support-subject').fill('Problema del gruppo');await page.locator('#support-message').fill('Richiesta visibile a tutti i membri');
   await page.locator('#support-create-button').click();await page.waitForFunction(()=>window.fixture.calls.some(c=>c.name==='open_group_support_ticket'&&c.args.p_visibility==='group'&&c.args.p_line===null));
   await page.locator('#support-reply-body').fill('Risposta del partecipante');await page.locator('#support-reply-button').click();
   await page.waitForFunction(()=>window.fixture.calls.some(c=>c.name==='post_support_message'));
   await page.locator('#support-group-reference').selectOption('group-1');await page.locator('#support-group-visibility').selectOption('personal');
   await page.locator('#support-group-line').selectOption('own-line');await page.locator('#support-group-payment').selectOption('own-payment');
   await page.locator('#support-subject').fill('Pagamento personale');await page.locator('#support-message').fill('Questo pagamento resta riservato');await page.locator('#support-create-button').click();
   await page.waitForFunction(()=>window.fixture.calls.some(c=>c.name==='open_group_support_ticket'&&c.args.p_visibility==='personal'&&c.args.p_payment==='own-payment'&&c.args.p_line==='own-line'));
   assert.deepEqual(errors,[]);console.log(JSON.stringify({browser:name,viewport,result:'PASS',scenario:'shared group tickets, member replies, private payment references'}));await page.close();
  }await browser.close();browser=null;
 }
}finally{await browser?.close();server.kill('SIGTERM');}
