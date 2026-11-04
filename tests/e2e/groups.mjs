import {chromium,firefox,webkit} from 'playwright';
import {createServer} from 'vite';
import assert from 'node:assert/strict';
import {groupFixture} from './groups-fixture.mjs';
const origin='http://127.0.0.1:5181';
const server=await createServer({base:'/',server:{host:'127.0.0.1',port:5181,strictPort:true},plugins:[{name:'group-fixture',configureServer(vite){vite.middlewares.use('/__groups-qa',(_req,res)=>{res.setHeader('Content-Type','text/html');res.end(groupFixture);});}}]});
await server.listen();let browser;
const engines=process.env.GROUP_BROWSER==='chromium'?{chromium}:{chromium,firefox,webkit};
try{
 for(const[name,engine] of Object.entries(engines)){
  browser=await engine.launch({headless:true});
  for(const viewport of [{width:1440,height:1000},{width:390,height:844}]){
   const context=await browser.newContext({viewport,geolocation:{latitude:45.5,longitude:9.3,accuracy:35},permissions:['geolocation']});
   const page=await context.newPage(),errors=[];page.on('pageerror',error=>errors.push(error.message));
   await page.goto(origin+'/__groups-qa');
   await page.getByRole('button',{name:'Apri gruppo'}).waitFor();
   assert.equal(await page.locator('#groups-create-form').isVisible(),false);
   assert.equal(await page.locator('#groups-join-form').isVisible(),false);
   await page.getByText('Crea un gruppo',{exact:true}).click();
   assert.equal(await page.locator('#groups-create-form').isVisible(),true);
   await page.getByText('Crea un gruppo',{exact:true}).click();
   await page.getByRole('button',{name:'Apri gruppo'}).click();
   await page.locator('#group-products input').first().waitFor();
   assert.equal(await page.locator('#groups-overview').isVisible(),false);
   assert.equal(await page.locator('#group-manage').getAttribute('open'),null);
   assert.equal(await page.locator('#group-payments-panel').getAttribute('open'),null);
   assert.match(await page.locator('#group-detail-meta').innerText(),/Bozza · Coordinatore · Iscritto/);
   await page.getByLabel('Quantità di Panino').fill('2');
   await page.getByRole('button',{name:'Conferma ordine di gruppo'}).click();
   await page.getByText(/Hai quantità non salvate/).waitFor();
   await page.getByRole('button',{name:'Ho finito',exact:true}).click();
   await page.getByRole('button',{name:'Modifica il mio ordine',exact:true}).waitFor();
   const calls=await page.evaluate(()=>window.fixture.calls.filter(x=>['replace_group_personal_cart','set_group_personal_ready'].includes(x.name)));
   assert.deepEqual(calls.map(x=>x.name),['replace_group_personal_cart','set_group_personal_ready']);
   assert.equal(calls[0].args.p_items[0].quantity,2);
   await page.getByText('Impostazioni del gruppo',{exact:true}).click();
   assert.equal(await page.getByRole('button',{name:'Rigenera link invito'}).isVisible(),true);
   await page.getByRole('button',{name:'← Tutti i gruppi'}).click();
   await page.getByText('Entra in un gruppo',{exact:true}).click();
   await page.getByLabel('Link o codice invito').fill('11111111-1111-4111-8111-111111111111');
   await page.getByRole('button',{name:'Verifica posizione e partecipa'}).click();
   await page.waitForFunction(()=>window.fixture.calls.some(c=>c.name==='join_group_draft')||document.getElementById('groups-feedback').dataset.type==='error',null,{timeout:27000});
   const locationMessage=await page.locator('#groups-feedback').innerText();
   const join=await page.evaluate(()=>window.fixture.calls.find(c=>c.name==='join_group_draft'));
   assert.ok(join,'Ingresso gruppo non completato in '+name+': '+locationMessage);
   assert.equal(join.args.p_accuracy_m,35);
   await page.getByRole('button',{name:'← Tutti i gruppi'}).click();
   await page.evaluate(()=>window.fixture.setGuest());
   await page.waitForFunction(()=>document.getElementById('groups-create-disclosure').hidden);
   const overflow=await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth);
   assert.ok(overflow<=3,'horizontal overflow: '+overflow);
   assert.deepEqual(errors,[]);
   console.log(JSON.stringify({browser:name,viewport,result:'PASS',scenario:'compact group overview, saved cart, settings, guest access and location'}));
   await context.close();
  }
  await browser.close();browser=null;
 }
}finally{await browser?.close();await server.close();}
