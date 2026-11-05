// Staff and admin controllers are a separate chunk. Customers must never fetch
// it; staff contexts must open only after it is listening; a failed download
// must keep staff sections closed. Fictional demo data only.
import {chromium,firefox,webkit} from 'playwright';
import assert from 'node:assert/strict';
import {startDemoServer} from './support/demo-server.mjs';
const engines={chromium,firefox,webkit};
const names=(process.env.E2E_BROWSERS||'chromium,firefox,webkit').split(',');
const {server,origin}=await startDemoServer(Number(process.env.ROLE_MODULES_PORT||5191));
const isStaffChunk=url=>/\/src\/js\/staff-modules\.js|\/assets\/staff-modules-/.test(url);
try{
 for(const name of names){
  const browser=await engines[name].launch();
  try{
   // 1. A student never downloads staff code.
   {
    const page=await browser.newPage({viewport:{width:390,height:844}});const errors=[],staff=[];
    page.on('pageerror',e=>errors.push(e.message));
    page.on('request',r=>{if(isStaffChunk(r.url()))staff.push(r.url());});
    await page.goto(origin+'/__demo?as=student#menu');
    await page.waitForFunction(()=>window.demo?.ready&&document.body.dataset.activeRole==='customer');
    await page.waitForTimeout(800);
    assert.deepEqual(staff,[],name+': customer fetched the staff chunk');
    assert.equal(await page.evaluate(()=>window.demo.roleModules.loaded),false);
    for(const id of ['cash-workspace','offline-terminal','admin-overview','platform-overview'])
     assert.equal(await page.locator('#'+id).isVisible(),false,name+': '+id+' visible to a customer');
    assert.deepEqual(errors,[],name+': '+errors.join('; '));
    await page.close();
   }
   // 2. A bartender gets working staff controllers on first paint.
   {
    const page=await browser.newPage({viewport:{width:1440,height:900}});const errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    await page.goto(origin+'/__demo?as=bartender#cash-workspace');
    await page.waitForFunction(()=>window.demo?.ready&&document.body.dataset.activeRole==='bartender');
    assert.equal(await page.evaluate(()=>window.demo.roleModules.loaded),true);
    await page.locator('#cash-workspace').waitFor({state:'visible'});
    assert.equal(await page.evaluate(()=>location.hash),'#cash-workspace','restored route lost while loading');
    // The cash controller received the context: its bar selector is filled.
    await page.waitForFunction(()=>document.querySelectorAll('#cash-bar option').length>0);
    await page.evaluate(()=>{location.hash='offline-terminal';});
    await page.locator('#offline-terminal').waitFor({state:'visible'});
    assert.deepEqual(errors,[],name+': '+errors.join('; '));
    await page.close();
   }
   // 3. If the chunk cannot be downloaded, staff sections stay closed.
   {
    const context=await browser.newContext({viewport:{width:390,height:844}});
    await context.route(url=>isStaffChunk(url.href),route=>route.abort());
    const page=await context.newPage();
    await page.goto(origin+'/__demo?as=bartender#cash-workspace');
    await page.waitForFunction(()=>window.demo?.ready);
    await page.waitForFunction(()=>/strumenti del personale/.test(document.getElementById('school-access-status')?.textContent||''));
    assert.notEqual(await page.evaluate(()=>document.body.dataset.activeRole),'bartender');
    await page.locator('#accesso').waitFor({state:'visible'});
    for(const id of ['cash-workspace','offline-terminal','staff-orders-section'])
     assert.equal(await page.locator('#'+id).isVisible(),false,name+': '+id+' opened without its controller');
    await context.close();
   }
   console.log(name+': role modules ok');
  }finally{await browser.close();}
 }
}finally{await server.close();}
