import {chromium,firefox,webkit} from 'playwright';
import {spawn} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
import assert from 'node:assert/strict';
const origin='http://127.0.0.1:5175';
const fixture=`<!doctype html><html lang="it"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/src/css/base.css"></head><body><main id="main-content"></main>
<script type="module">
import {initializeOrderWorkflows} from '/src/js/features/operations/workflows.js';
import {initializeCompletionUI} from '/src/js/features/operations/completion-ui.js';
import {readClassNames} from '/src/js/features/operations/class-import.js';
import {workbookBytes} from '/src/js/features/shell/report-files.js';
window.fixture={calls:[],role:'bartender'};
const user={id:'fixture-user'},notice={id:'request-1',owner_id:'someone-else',order_id:'order-1',group_order_id:null,bar_id:'bar-1',state:'active',service_date:'2026-11-01',starts_at:'12:00:00',reason:'',lease_until:new Date(Date.now()+600000).toISOString()};
const client={auth:{onAuthStateChange(){},async getUser(){return{data:{user}}}},
 async rpc(name,args){window.fixture.calls.push({name,args});
  if(name==='list_order_approvals')return{data:window.fixture.role==='bartender'?[{...notice}]:[]};
  if(name==='decide_order_approval'){notice.state='approved';return{data:null}};
  if(name==='platform_onboard_school')return{data:{school_id:'created-school',bar_id:'created-bar'}};
  if(['list_order_changes','list_cash_refund_obligations','my_payment_documents','list_staff_group_orders','list_my_confirmed_group_orders','list_school_promotions'].includes(name))return{data:[]};
  return{data:null};},
 from(name){const q={select(){return this},eq(){return this},order(){return this},limit(){return this},then(resolve,reject){return Promise.resolve({data:name==='bars'?[{id:'bar-1',name:'School bar'}]:[]}).then(resolve,reject)}};return q}
};
initializeCompletionUI(client);initializeOrderWorkflows(client);
window.fixture.switchRole=role=>{window.fixture.role=role;window.dispatchEvent(new CustomEvent('breakapp:workspace-context',{detail:{role,schoolId:'school-1',verified:true}}));document.getElementById('workflow-center').hidden=false};
window.fixture.testExcel=async()=>{
 const bytes=workbookBytes([{name:'Classi',rows:[['Classe'],['5A'],['5B'],['5A']]}]);
 return readClassNames(new File([bytes],'classi.xlsx'));
};
window.fixture.ready=true;
</script></body></html>`;
const server=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','5175','--strictPort'],{stdio:'ignore',env:{...process.env,GITHUB_PAGES_BASE:'/'}});
let browser;
try{
 for(let i=0;i<50;i++){try{if((await fetch(origin)).ok)break;}catch{}await delay(200);}
 for(const[name,engine]of Object.entries({chromium,firefox,webkit})){
  browser=await engine.launch({headless:true});
  for(const viewport of [{width:1440,height:900},{width:390,height:844}]){
   const page=await browser.newPage({viewport}),errors=[];page.on('pageerror',e=>errors.push(e.message));
   await page.route(origin+'/fixture',r=>r.fulfill({contentType:'text/html',body:fixture}));await page.goto(origin+'/fixture');
   await page.waitForFunction(()=>window.fixture?.ready);await page.evaluate(()=>window.fixture.switchRole('bartender'));
   await page.getByRole('button',{name:'Approva',exact:true}).click();
   await page.waitForFunction(()=>window.fixture.calls.some(c=>c.name==='decide_order_approval'&&c.args.p_approve===true));
   await page.getByLabel('Sono in servizio e disponibile per le approvazioni').check();
   await page.waitForFunction(()=>window.fixture.calls.some(c=>c.name==='set_staff_service_presence'&&c.args.p_present===true));
   await page.evaluate(()=>window.fixture.switchRole('school_admin'));
   await page.getByRole('heading',{name:'Coupon e bundle'}).waitFor();
   const promotion=page.locator('article').filter({has:page.getByRole('heading',{name:'Coupon e bundle'})});
   await promotion.getByLabel('Codice coupon',{exact:true}).fill('TEST20');await promotion.getByLabel('Titolo',{exact:true}).fill('Test discount');
   await promotion.getByLabel('Inizio',{exact:true}).fill('2026-10-27T08:00');await promotion.getByLabel('Fine',{exact:true}).fill('2026-11-01T18:00');
   await promotion.getByRole('button',{name:'Crea promozione'}).click();
   await page.waitForFunction(()=>window.fixture.calls.some(c=>c.name==='save_school_promotion'&&c.args.p_code==='TEST20'));
   assert.deepEqual(await page.evaluate(()=>window.fixture.testExcel()),['5A','5B']);
   await page.evaluate(()=>window.fixture.switchRole('platform_admin'));
   const onboarding=page.locator('article').filter({has:page.getByRole('heading',{name:'Dati della scuola'})});
   await onboarding.getByLabel('Identificativo della scuola (es. liceo-verdi)').fill('test-school');await onboarding.getByLabel('Nome della scuola',{exact:true}).fill('Test school');
   await onboarding.getByLabel('Nome del bar',{exact:true}).fill('Test bar');await onboarding.getByLabel('Latitudine').fill('45');await onboarding.getByLabel('Longitudine').fill('9');
   await onboarding.getByLabel('Email verificata del primo Admin').fill('admin@test.invalid');await onboarding.getByRole('button',{name:'Crea scuola e bar'}).click();
   await page.waitForFunction(()=>window.fixture.calls.some(c=>c.name==='platform_onboard_school'&&c.args.p_slug==='test-school'));
   const width=await page.evaluate(()=>({scroll:document.documentElement.scrollWidth,viewport:innerWidth}));assert.ok(width.scroll<=width.viewport+3);
   assert.deepEqual(errors,[]);console.log(JSON.stringify({browser:name,viewport,result:'PASS',scenario:'approvals, presence, promotion, XLSX import, onboarding'}));await page.close();
  }
  await browser.close();browser=null;
 }
}finally{await browser?.close();server.kill('SIGTERM');}
