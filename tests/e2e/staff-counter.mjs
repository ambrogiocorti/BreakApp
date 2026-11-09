// Bartender counter: one tap to «Pronto», payment and delivery in one
// confirmation, and «numero + Invio» from the search field. Fictional data only.
import {chromium,firefox,webkit} from 'playwright';
import assert from 'node:assert/strict';
import {startDemoServer} from './support/demo-server.mjs';

const engines=Object.entries({chromium,firefox,webkit})
 .filter(([name])=>!process.env.E2E_BROWSERS||process.env.E2E_BROWSERS.split(',').includes(name));
const {server,origin}=await startDemoServer(Number(process.env.STAFF_PORT||5192));
const calls=page=>page.evaluate(()=>window.demo.client.db.state.rpcCalls
 .filter(c=>['advance_individual_order','record_individual_counter_payment'].includes(c.name))
 .map(c=>c.name+':'+(c.args.p_next||c.args.p_method)));
try{
 for(const [name,engine] of engines){
  const browser=await engine.launch();
  for(const viewport of [{width:1280,height:800},{width:390,height:844}]){
   const page=await browser.newPage({viewport});
   const errors=[];page.on('pageerror',e=>errors.push(e.message));
   await page.goto(origin+'/__demo?as=bartender#staff-orders-section');
   await page.waitForFunction(()=>window.demo?.ready);
   const card=no=>page.locator(`.staff-order-card:has(.ticket-no:text-is("#${no}"))`);

   // Confirmed order: «Pronto» is the main button, one tap, no dialog.
   if(viewport.width<1024)await page.getByRole('tab',{name:/Da preparare/}).click();
   const confirmed=card(128);
   assert.equal(await confirmed.locator('.order-actions .button-primary').innerText(),'Pronto');
   await confirmed.locator('.order-actions .button-primary').click();
   await page.waitForFunction(()=>window.demo.client.db.state.rpcCalls.some(c=>c.args?.p_next==='ready'));

   // Ready and unpaid: «Contanti» (incassa e consegna) asks once, focus on Conferma, then pays and delivers.
   if(viewport.width<1024)await page.getByRole('tab',{name:/Pronti/}).click();
   const due=card(126);
   assert.equal(await due.locator('.order-actions .button-primary').innerText(),'Contanti');
   assert.match(await due.locator('.order-actions-caption').innerText(),/Incassa e consegna/);
   await due.locator('.order-actions .button-primary').click();
   const dialog=page.locator('#staff-action-confirm');
   await dialog.waitFor({state:'visible'});
   assert.match(await dialog.innerText(),/#126.*5,20.*contanti/s);
   assert.equal(await page.evaluate(()=>document.activeElement?.id),'staff-action-approve');
   await page.keyboard.press('Enter');
   await page.waitForFunction(()=>window.demo.client.db.state.rpcCalls.some(c=>c.args?.p_next==='delivered'));
   const sequence=await calls(page);
   assert.deepEqual(sequence.slice(-2),['record_individual_counter_payment:cash','advance_individual_order:delivered']);

   // Cancelling the dialog records nothing.
   const before=(await calls(page)).length;
   await card(141).locator('.order-actions .button-primary').click();
   await dialog.waitFor({state:'visible'});
   await page.locator('#staff-action-cancel').click();
   await page.waitForTimeout(150);
   assert.equal((await calls(page)).length,before);

   // «125» + Enter focuses that order's main button (a paid, ready order: «Consegna»).
   await page.fill('#staff-search','125');
   await page.press('#staff-search','Enter');
   await page.waitForFunction(()=>document.activeElement?.textContent==='Consegna');
   assert.equal(await page.evaluate(()=>document.activeElement.closest('.staff-order-card')?.querySelector('.ticket-no')?.textContent),'#125');

   assert.deepEqual(errors,[]);
   console.log(JSON.stringify({browser:name,viewport,result:'PASS',scenario:'bartender counter: one-tap ready, pay and deliver in one confirmation, number + Enter'}));
   await page.close();
  }
  await browser.close();
 }
}finally{await server.close();}
