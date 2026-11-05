import {chromium,firefox,webkit} from 'playwright';
import {createServer} from 'vite';
import assert from 'node:assert/strict';
import {checkoutFixture} from './checkout-fixture.mjs';
const origin='http://127.0.0.1:5182';
const server=await createServer({base:'/',server:{host:'127.0.0.1',port:5182,strictPort:true},plugins:[{name:'checkout-fixture',configureServer(vite){vite.middlewares.use('/__checkout-qa',(_req,res)=>{res.setHeader('Content-Type','text/html');res.end(checkoutFixture);});}}]});
await server.listen();let browser;
const engines=process.env.CHECKOUT_BROWSER==='chromium'?{chromium}:{chromium,firefox,webkit};
try{
 for(const[name,engine] of Object.entries(engines)){
  browser=await engine.launch({headless:true});
  for(const viewport of [{width:1440,height:1000},{width:390,height:844}]){
   const page=await browser.newPage({viewport}),errors=[];page.on('pageerror',error=>errors.push(error.message));
   await page.goto(origin+'/__checkout-qa');await page.waitForFunction(()=>window.fixture?.ready);
   await page.getByRole('button',{name:'Aggiungi panino di prova'}).click();
   await page.locator('#cart-open').click();await page.locator('#cart-checkout').waitFor({state:'visible'});
   await page.waitForFunction(()=>!document.getElementById('cart-checkout').disabled);
   await page.locator('#cart-checkout').click();await page.locator('#order-next').click();
   assert.equal(await page.getByLabel('Codice sconto',{exact:true}).isVisible(),false);
   await page.getByText('Hai un codice sconto?').click();await page.getByLabel('Codice sconto',{exact:true}).fill('SCUOLA');
   await page.getByRole('button',{name:'Verifica posizione e conferma ordine'}).click();
   await page.waitForFunction(()=>window.fixture.watch!==null);await page.evaluate(()=>window.fixture.position(240));
   await page.getByText(/Posizione approssimativa/).waitFor();
   assert.equal(await page.evaluate(()=>window.fixture.calls.some(x=>x.name==='submit_promoted_order')),false);
   await page.locator('#order-stepper .ba-dialog-close button').click();
   await page.waitForFunction(()=>window.fixture.cleared.includes(17));
   assert.equal(await page.evaluate(()=>window.fixture.calls.some(x=>x.name==='submit_promoted_order')),false);
   await page.locator('#cart-open').click();await page.locator('#cart-checkout').click();
   await page.locator('#order-next').click();
   await page.getByRole('button',{name:'Verifica posizione e conferma ordine'}).click();
   await page.waitForFunction(()=>window.fixture.watch!==null);await page.evaluate(()=>window.fixture.position(35));
   await page.waitForFunction(()=>window.fixture.calls.some(x=>x.name==='submit_promoted_order'));
   const order=await page.evaluate(()=>window.fixture.calls.find(x=>x.name==='submit_promoted_order'));
   assert.equal(order.args.p_accuracy,35);assert.equal(order.args.p_code,'SCUOLA');
   assert.equal(order.args.p_items[0].quantity,1);
   await page.locator('#order-stepper').waitFor({state:'hidden'});
   await page.getByRole('button',{name:'Aggiungi panino di prova'}).click();
   await page.locator('#cart-open').click();await page.locator('#cart-checkout').click();await page.locator('#order-next').click();
   await page.getByRole('button',{name:'Verifica posizione e conferma ordine'}).click();
   await page.waitForFunction(()=>window.fixture.watch!==null);
   await page.evaluate(()=>window.fixture.logout());
   await page.waitForFunction(()=>!document.getElementById('order-stepper').open&&window.fixture.watch===null);
   assert.equal(await page.evaluate(()=>window.fixture.calls.filter(x=>x.name==='submit_promoted_order').length),1);
   assert.deepEqual(errors,[]);console.log(JSON.stringify({browser:name,viewport,result:'PASS',scenario:'simplified checkout, accurate position, cancellation and coupon'}));
   await page.close();
  }
  await browser.close();browser=null;
 }
}finally{await browser?.close();await server.close();}
