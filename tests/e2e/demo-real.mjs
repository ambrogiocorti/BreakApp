// Manual/explicit QA only: this exercises the named DEV demo tenant and
// cancels its synthetic unpaid order through the normal customer interface.
import {chromium} from 'playwright';
import assert from 'node:assert/strict';

if(process.env.BREAKAPP_DEMO_E2E!=='yes')throw Error('Test DEV non autorizzato dalla workflow.');
const url='https://ambrogiocorti.github.io/BreakApp/';
const school='DEMO BreakApp - solo ordini di prova';
const name='QA Demo '+Date.now();
let browser,context,page,submitted=false,created=false,cancelled=false,stage='avvio',failure;
try{
 browser=await chromium.launch({headless:true});
 context=await browser.newContext({viewport:{width:390,height:844},
  geolocation:{latitude:45.5231,longitude:9.3133,accuracy:20},permissions:['geolocation']});
 page=await context.newPage();page.setDefaultTimeout(30000);
 stage='accesso ospite demo';
 await page.goto(url,{waitUntil:'domcontentloaded'});
 await page.getByRole('option',{name:school,exact:true}).waitFor({state:'attached'});
 await page.getByRole('combobox',{name:'Scuola dell’ospite'}).selectOption({label:school});
 await page.getByRole('textbox',{name:'Nome e cognome'}).fill(name);
 await page.getByRole('button',{name:'Accedi come ospite'}).click();
 await page.getByRole('heading',{name:'Menu',exact:true}).waitFor({state:'visible',timeout:60000});
 stage='carrello e fascia';
 await page.getByRole('button',{name:'Aggiungi DEMO - Panino al carrello'}).click();
 await page.getByRole('button',{name:/Carrello · 1 articoli/}).click();
 await page.getByRole('button',{name:'Continua con il ritiro'}).click();
 const slot=page.getByRole('combobox',{name:'Scegli una fascia tra quelle effettivamente configurate'});
 assert.ok(await slot.locator('option').count()>0,'Nessuna fascia demo disponibile');
 await page.getByRole('button',{name:'Continua',exact:true}).click();
 stage='prenotazione con posizione fittizia';submitted=true;
 await page.getByRole('button',{name:'Verifica posizione e conferma ordine'}).click();
 await page.waitForURL(/#orders$/,{timeout:60000});
 const card=page.locator('#orders-list article').filter({hasText:'DEMO - Panino'}).first();
 await card.waitFor({state:'visible',timeout:30000});
 assert.match(await card.innerText(),/2,50\s*€/);
 created=true;
 console.log('Ordine demo creato dal browser con posizione fittizia; nessun pagamento effettuato.');
}catch(error){failure=error;console.error('Prova interrotta durante: '+stage);}
finally{
 if(page&&submitted){
  try{
   stage='annullamento ordine demo';
   // On narrow screens this route lives behind the "Altro" menu.
   await page.getByRole('button',{name:'Altro',exact:true}).click({timeout:15000});
   await page.getByRole('link',{name:'Richieste e modifiche',exact:true}).click({timeout:15000});
   const cancel=page.locator('#workflow-center').getByRole('button',{name:'Annulla ordine',exact:true});
   await cancel.waitFor({state:'visible',timeout:30000});
   page.once('dialog',async dialog=>{
    if(dialog.type()==='confirm'&&dialog.message()==='Annullare e avviare gli eventuali rimborsi?')await dialog.accept();
    else await dialog.dismiss();
   });
   await cancel.click();
   await page.locator('#workflow-center [role="status"]').filter({hasText:'Operazione registrata sul server.'}).waitFor({state:'visible',timeout:30000});
   await page.getByRole('link',{name:'I miei ordini',exact:true}).click();
   await page.locator('#orders-refresh').click();
   await page.locator('#orders-list article').filter({hasText:'DEMO - Panino'}).getByText(/Annullato/).waitFor({state:'visible',timeout:30000});
   cancelled=true;console.log('Ordine demo annullato dal browser.');
  }catch(error){console.error('Pulizia non confermata durante '+stage+' ('+error.name+'): controllare gli ordini QA della scuola demo.');}
 }
 await context?.close();await browser?.close();
}
if(failure||!created||!cancelled)throw Error('Collaudo demo non completato; verificare la fase e la pulizia sopra.');
