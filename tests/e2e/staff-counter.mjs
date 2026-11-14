// Banco veloce: un tocco per incassare, battere lo scontrino e consegnare,
// tre secondi per annullare, pagamento con carta abbandonato chiuso da solo,
// rimborso in due tocchi con la cassa controllata prima. Dati inventati.
import {chromium,firefox,webkit} from 'playwright';
import assert from 'node:assert/strict';
import {startDemoServer} from './support/demo-server.mjs';

const engines=Object.entries({chromium,firefox,webkit})
 .filter(([name])=>!process.env.E2E_BROWSERS||process.env.E2E_BROWSERS.split(',').includes(name));
const {server,origin}=await startDemoServer(Number(process.env.STAFF_PORT||5192));
const WATCHED=['advance_individual_order','record_individual_counter_payment','mark_order_receipts_issued','fn:stripe-checkout-cancel','request_completed_order_refund','confirm_cash_refund_return','record_cash_operation','exchange_order_item'];
const calls=page=>page.evaluate(names=>window.demo.client.db.state.rpcCalls
 .filter(c=>names.includes(c.name))
 .map(c=>c.name+':'+(c.args?.p_order_id||c.args?.p_order||c.args?.order_id||'')+':'+(c.args?.p_next||c.args?.p_method||c.args?.p_action||'')),WATCHED);
const since=async(page,before)=>(await calls(page)).slice(before);
try{
 for(const [name,engine] of engines){
  const browser=await engine.launch();
  for(const viewport of [{width:1280,height:800},{width:390,height:844}]){
   const page=await browser.newPage({viewport});
   const errors=[];page.on('pageerror',e=>{if(!e.message.includes('demo.invalid'))errors.push(e.message);});
   await page.goto(origin+'/__demo?as=bartender#staff-orders-section');
   await page.waitForFunction(()=>window.demo?.ready);
   // Pagamento con carta lasciato a meta' sull'ordine #141: si chiude da solo.
   await page.evaluate(()=>{
    const rpc=window.demo.client.db;window.demo.openCheckout=new Set(['order-141']);
    const original=window.demo.client.rpc.bind(window.demo.client);
    window.demo.client.rpc=async(name,args)=>name==='staff_open_checkout'
     ?(rpc.state.rpcCalls.push({name,args}),{data:{open:window.demo.openCheckout.has(args.p_order),status:'requires_action'},error:null})
     :original(name,args);
    window.demo.client.functions.invoke=async(fn,options)=>{rpc.state.rpcCalls.push({name:'fn:'+fn,args:options?.body});window.demo.openCheckout.delete(options?.body?.order_id);return {data:{status:'cancelled'},error:null};};
   });
   const card=no=>page.locator(`#staff-orders-list .staff-order-card:has(.ticket-no:text-is("#${no}"))`);
   await card(126).waitFor();

   // Pronto e da incassare: un tocco su «Contanti 3,00 €», niente finestre.
   const due=card(126);
   assert.equal((await due.locator('.order-actions .button-primary').innerText()).replace(/\s/g,' '),'Contanti 3,00 €');
   let before=(await calls(page)).length;
   await due.locator('.order-actions .button-primary').click();
   await due.locator('.ticket-undo').waitFor();
   assert.match((await due.locator('.ticket-undo').innerText()).replace(/\s/g,' '),/#126: incassati 3,00 € in contanti e consegnato/);
   assert.equal(await page.locator('dialog[open]').count(),0);
   await page.waitForFunction(n=>window.demo.client.db.state.rpcCalls.filter(c=>c.args?.p_next==='delivered').length>=n,1,{timeout:6000});
   assert.deepEqual(await since(page,before),[
    'record_individual_counter_payment:order-126:cash','mark_order_receipts_issued:order-126:','advance_individual_order:order-126:delivered']);

   // Tocco sbagliato: «Annulla» entro tre secondi e non parte niente.
   before=(await calls(page)).length;
   await card(130).locator('.order-actions .button-primary').click();
   await card(130).getByRole('button',{name:/^Annulla/}).click();
   await page.waitForTimeout(3400);
   assert.deepEqual(await since(page,before),[]);

   // Da preparare e da incassare: lo stesso tocco lo segna pronto, incassa e consegna.
   before=(await calls(page)).length;
   await card(128).locator('.order-actions .button-primary').click();
   await page.waitForFunction(()=>window.demo.client.db.state.rpcCalls.some(c=>c.args?.p_order_id==='order-128'&&c.args?.p_next==='delivered'),null,{timeout:6000});
   assert.deepEqual(await since(page,before),[
    'advance_individual_order:order-128:ready','record_individual_counter_payment:order-128:cash','mark_order_receipts_issued:order-128:','advance_individual_order:order-128:delivered']);

   // Carta abbandonata su #141: chiusa in automatico, poi il POS. Nessuna domanda.
   before=(await calls(page)).length;
   await card(141).getByRole('button',{name:/^POS/}).click();
   await page.waitForFunction(()=>window.demo.client.db.state.rpcCalls.some(c=>c.args?.p_order_id==='order-141'&&c.args?.p_next==='delivered'),null,{timeout:6000});
   assert.deepEqual(await since(page,before),[
    'fn:stripe-checkout-cancel:order-141:','record_individual_counter_payment:order-141:external_pos','mark_order_receipts_issued:order-141:','advance_individual_order:order-141:delivered']);
   assert.equal(await page.locator('dialog[open]').count(),0);

   // «Pronto» per avvisare il cliente parte subito.
   before=(await calls(page)).length;
   await card(132).getByRole('button',{name:/^Pronto/}).click();
   await page.waitForFunction(()=>window.demo.client.db.state.rpcCalls.some(c=>c.args?.p_order_id==='order-132'&&c.args?.p_next==='ready'));

   // Da tastiera: «125» + Invio porta su «Consegna», Invio consegna.
   await page.fill('#staff-search','125');
   await page.press('#staff-search','Enter');
   await page.waitForFunction(()=>document.activeElement?.textContent==='Consegna');
   before=(await calls(page)).length;
   await page.keyboard.press('Enter');
   await page.waitForFunction(()=>window.demo.client.db.state.rpcCalls.some(c=>c.args?.p_order_id==='order-125'&&c.args?.p_next==='delivered'),null,{timeout:6000});
   assert.deepEqual(await since(page,before),['mark_order_receipts_issued:order-125:','advance_individual_order:order-125:delivered']);

   // Rimborso: il numero trova anche gli ordini conclusi; due tocchi.
   await page.fill('#staff-search','120');
   await card(120).getByRole('button',{name:'Rimborsa ordine numero 120'}).click();
   const refund=page.locator('#staff-refund-dialog');
   await refund.waitFor({state:'visible'});
   before=(await calls(page)).length;
   await refund.getByRole('button',{name:'Prodotto sbagliato'}).click();
   await refund.waitFor({state:'hidden'});
   assert.deepEqual(await since(page,before),['request_completed_order_refund:order-120:','confirm_cash_refund_return::','mark_order_receipts_issued:order-120:']);
   assert.match((await page.locator('#staff-orders-feedback').innerText()).replace(/\s/g,' '),/#120 rimborsato.*1,80/);

   // Cassa chiusa: il rimborso la apre nello stesso tocco, prima di rimborsare.
   await page.evaluate(()=>{const ws=window.demo.client.db;ws.savedCash=ws.state.cashClosed=true;});
   await page.evaluate(()=>{const c=window.demo.client;const original=c.rpc.bind(c);
    c.rpc=async(name,args)=>name==='cash_workspace'&&c.db.state.cashClosed?(c.db.state.rpcCalls.push({name,args}),{data:{sessions:[],entries:[]},error:null}):original(name,args);});
   await card(120).getByRole('button',{name:'Rimborsa ordine numero 120'}).click();
   await page.locator('#staff-refund-drawer').waitFor({state:'visible'});
   await page.fill('#staff-refund-opening','50,00');
   before=(await calls(page)).length;
   await refund.getByRole('button',{name:'Il cliente ha cambiato idea'}).click();
   await refund.waitFor({state:'hidden'});
   const steps=await since(page,before);
   assert.equal(steps[0],'record_cash_operation::open');
   assert.equal(steps[1],'request_completed_order_refund:order-120:');
   const opened=await page.evaluate(()=>window.demo.client.db.state.rpcCalls.findLast(c=>c.name==='record_cash_operation').args);
   assert.equal(opened.p_amount,5000);
   await page.evaluate(()=>{window.demo.client.db.state.cashClosed=false;});

   // Cambio prodotto: focaccia (1,80) -> acqua (0,80), la differenza torna in contanti.
   await card(120).getByRole('button',{name:'Rimborsa ordine numero 120'}).click();
   await refund.waitFor({state:'visible'});
   await page.locator('input[name="staff-refund-mode"][value="exchange"]').check();
   await page.waitForFunction(()=>document.querySelector('#staff-exchange-in')?.options.length>2);
   await page.selectOption('#staff-exchange-in','p-acqua');
   assert.match(await page.locator('#staff-exchange-diff').innerText(),/tornano 1,00/);
   assert.equal(await page.locator('#staff-exchange-pay').isHidden(),true);
   await refund.getByRole('button',{name:'Prodotto sbagliato'}).click();
   await refund.waitFor({state:'hidden'});
   const exchange=await page.evaluate(()=>window.demo.client.db.state.rpcCalls.find(c=>c.name==='exchange_order_item')?.args);
   assert.equal(exchange.p_product_out,'p-focaccia');assert.equal(exchange.p_product_in,'p-acqua');assert.equal(exchange.p_method,null);

   // Nessuno scorrimento orizzontale.
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true);
   assert.deepEqual(errors,[]);
   console.log(JSON.stringify({browser:name,viewport,result:'PASS',scenario:'banco: un tocco per incassare e consegnare, annulla in 3 s, carta abbandonata chiusa da sola, rimborso in due tocchi con cassa aperta al volo, cambio prodotto'}));
   await page.close();
  }
  await browser.close();
 }
}finally{await server.close();}
