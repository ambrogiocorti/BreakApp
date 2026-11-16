import {chromium,firefox,webkit} from 'playwright';
import {createServer} from 'vite';
import assert from 'node:assert/strict';
import {groupFixture} from './groups-fixture.mjs';
// Stato del gruppo nel tag: dopo la conferma il tag segue l'ordine reale
// (in preparazione, pronto, consegnato…) e si aggiorna da solo.
const origin='http://127.0.0.1:5182';
const server=await createServer({base:'/',server:{host:'127.0.0.1',port:5182,strictPort:true},plugins:[{name:'group-fixture',configureServer(vite){vite.middlewares.use('/__groups-qa',(_req,res)=>{res.setHeader('Content-Type','text/html');res.end(groupFixture);});}}]});
await server.listen();let browser;
const engines=process.env.GROUP_BROWSER==='chromium'?{chromium}:{chromium,firefox,webkit};
const order={id:'99999999-9999-4999-8999-999999999999',status:'preparing',coordinator:true,total_cents:650,paid_cents:650,due_cents:0,pickup_token:null};
try{
 for(const[name,engine] of Object.entries(engines)){
  browser=await engine.launch({headless:true});
  for(const viewport of [{width:1440,height:1000},{width:390,height:844}]){
   const context=await browser.newContext({viewport});
   const page=await context.newPage(),errors=[];page.on('pageerror',error=>errors.push(error.message));
   await page.clock.install();
   await page.goto(origin+'/__groups-qa');
   await page.getByRole('button',{name:/Apri il gruppo/}).waitFor();
   await page.evaluate(o=>{window.fixture.detail.status='confirmed';window.fixture.order=o;},order);
   await page.getByRole('button',{name:'Aggiorna',exact:true}).click();
   await page.getByText('Elenco gruppi aggiornato.').waitFor();
   // L'elenco mostra lo stato dell'ordine, non «Confermato».
   assert.match(await page.locator('#groups-list').innerText(),/In preparazione/);
   await page.getByRole('button',{name:/Apri il gruppo/}).click();
   await page.locator('#group-confirmed-panel:not([hidden])').waitFor();
   const badge=page.locator('#group-detail-state');
   assert.equal(await badge.innerText(),'In preparazione');
   assert.equal(await badge.getAttribute('data-tone'),'warning');
   // Gruppo confermato: nessuno può più entrare, l'invito sparisce.
   assert.equal(await page.locator('#group-invite').isVisible(),false);
   // Il banco consegna: il tag e la scheda si aggiornano senza ricaricare.
   await page.evaluate(()=>{window.fixture.order.status='delivered';});
   await page.clock.runFor(16000);
   await page.waitForFunction(()=>document.getElementById('group-detail-state')?.textContent==='Consegnato');
   assert.match(await page.locator('#group-confirmed-summary').innerText(),/Consegnato/);
   // Ordine chiuso: niente più letture periodiche.
   const reads=()=>page.evaluate(()=>window.fixture.calls.filter(c=>c.name==='group_order_details').length);
   const before=await reads();
   await page.clock.runFor(60000);
   assert.equal(await reads(),before);
   await page.getByRole('button',{name:'← I tuoi gruppi'}).click();
   assert.match(await page.locator('#groups-list').innerText(),/Consegnato/);
   assert.deepEqual(errors,[]);
   console.log(JSON.stringify({browser:name,viewport,result:'PASS',scenario:'group tag follows real order status live, invite hidden after confirmation'}));
   await context.close();
  }
  await browser.close();browser=null;
 }
}finally{await browser?.close();await server.close();}
