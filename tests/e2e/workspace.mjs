import {chromium,firefox,webkit} from 'playwright';
import {createServer} from 'vite';
import assert from 'node:assert/strict';
import {workspaceFixture} from './workspace-fixture.mjs';
const origin='http://127.0.0.1:5178';
const server=await createServer({base:'/',server:{host:'127.0.0.1',port:5178,strictPort:true},plugins:[{name:'isolated-workspace-fixture',configureServer(vite){vite.middlewares.use('/__workspace-qa',(_req,res)=>{res.setHeader('Content-Type','text/html');res.end(workspaceFixture)})}}]});
await server.listen();let browser;
const engines=process.env.WORKSPACE_BROWSER==='chromium'?{chromium}:{chromium,firefox,webkit};
try{
 for(const[name,engine]of Object.entries(engines)){
  browser=await engine.launch({headless:true});
  for(const viewport of [{width:1440,height:1000},{width:768,height:1024},{width:390,height:844}]){
   let page=await browser.newPage({viewport});const errors=[];page.on('pageerror',error=>errors.push(error.message));
   await page.goto(origin+'/__workspace-qa');
   await page.getByRole('heading',{name:'Panoramica',exact:true}).waitFor();
   await page.locator('#platform-metrics .metric-card').first().waitFor();
   assert.deepEqual(await page.locator('#platform-metrics .metric-card>strong').allTextContents(),['3','2','3','1']);
   // Structural QA: this must be an actually new working layout, not Studio 02
   // behind updated colors. Use computed geometry in each rendering engine.
   const geometry=await page.evaluate(()=>{
    const box=id=>{const r=document.querySelector(id)?.getBoundingClientRect();return r?{x:r.x,y:r.y,w:r.width,h:r.height}:null;};
    return {header:box('.site-header'),strip:box('#workspace-sidebar'),
     navigation:box('#app-desktop-nav'),main:box('.app-main'),
     stage:box('#platform-overview .control-layout'),
     activity:box('#platform-overview .control-activity'),
     ledger:box('#platform-overview .control-side'),
     mobile:box('#app-mobile-nav'),roster:document.querySelectorAll('#platform-school-list .school-roster-row').length,
     ring:document.querySelectorAll('#platform-network svg').length,
     overflow:document.documentElement.scrollWidth-innerWidth};
   });
   assert.equal(geometry.roster,3,'overview must use the school roster with actual data');
   assert.equal(geometry.ring,0,'legacy decorative network ring still present');
   assert.ok(geometry.overflow<=3,'horizontal overflow '+JSON.stringify(geometry));
   if(viewport.width>1023){
    assert.ok(Math.abs(geometry.strip.y-72)<=2,'top workspace strip not installed');
    assert.ok(geometry.strip.w>viewport.width-4,'sidebar still consuming a side column');
    assert.ok(geometry.main.x<5,'main workspace not full width');
    assert.ok(geometry.activity.x<geometry.ledger.x,'control room has lost asymmetric columns');
   }else{
    assert.ok(geometry.main.x<5,'mobile workspace not full width');
    assert.ok(geometry.mobile.y>viewport.height-105,'mobile service dock is missing');
   }

   assert.equal(await page.locator('#platform-pilot-tools').isVisible(),false);
   assert.equal(await page.locator('#platform-overview').isVisible(),true);
   assert.equal(await page.getByRole('heading',{level:1}).count(),1);
   assert.equal(await page.locator('body').getAttribute('data-active-route'),'platform-overview');
   if(viewport.width<=760){
    // The accessible h1 remains in the document but the duplicated mobile
    // header must not steal the first screen from the actual indicators.
    const fold=await page.evaluate(()=>({header:document.querySelector('#workspace-page-head').getBoundingClientRect().height,ledger:document.querySelector('#platform-overview .control-side').getBoundingClientRect().top}));
    assert.ok(fold.header<=1,'duplicate mobile page heading occupies space');
    assert.ok(fold.ledger<viewport.height-150,'network indicators are still below the mobile fold: '+JSON.stringify(fold));
   }
   const layout=await page.evaluate(()=>({main:document.querySelector('.app-main').scrollTop,window:scrollY}));
   assert.equal(layout.main,0,JSON.stringify(layout));
   assert.equal(layout.window,0,JSON.stringify(layout));
   if(process.env.WORKSPACE_SCREENSHOTS)await page.screenshot({path:process.env.WORKSPACE_SCREENSHOTS+'/overview-'+name+'-'+viewport.width+'.png',fullPage:false,animations:'disabled'});
   if(viewport.width>1023)assert.equal(await page.locator('#workspace-sidebar').isVisible(),true);
   await page.getByRole('link',{name:'Vedi tutte'}).click();
   await page.getByRole('heading',{name:'Scuole',exact:true}).waitFor();
   assert.equal(await page.locator('body').getAttribute('data-active-route'),'platform-schools');
   await page.reload();
   await page.getByRole('heading',{name:'Scuole',exact:true}).waitFor();
   await page.locator('#platform-directory-list tbody tr').first().waitFor();
   await page.getByLabel('Cerca una scuola o un bar').fill('Caffè');
   assert.equal(await page.locator('#platform-directory-list tbody tr').count(),1);
   assert.match(await page.locator('#platform-directory-list').innerText(),/Marie Curie/);
   await page.getByLabel('Cerca una scuola o un bar').fill('nessuna-corrispondenza');
   await page.getByText('Nessun risultato',{exact:true}).waitFor();
   await page.getByLabel('Cerca una scuola o un bar').fill('');
   await page.locator('#platform-school-filter').selectOption('paused');
   assert.equal(await page.locator('#platform-directory-list tbody tr').count(),1);
   await page.getByRole('button',{name:'Riattiva Istituto Ada Lovelace',exact:true}).click();
   await page.getByRole('dialog').getByLabel('Motivazione',{exact:true}).fill('Servizio nuovamente disponibile');
   await page.getByRole('button',{name:'Riattiva scuola',exact:true}).click();
   await page.waitForFunction(()=>window.fixture.calls.some(c=>c.name==='platform_set_school_active'&&c.args.p_active===true));
   await page.getByText('Nessun risultato',{exact:true}).waitFor();
   await page.locator('#platform-school-filter').selectOption('all');
   await page.getByRole('link',{name:'Gestisci Liceo Leonardo',exact:true}).click();
   await page.getByRole('heading',{name:'Configurazione',exact:true}).waitFor();
   await page.waitForFunction(()=>document.getElementById('pilot-school').value==='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
   await page.getByRole('button',{name:'Completa attivazione Stripe TEST',exact:true}).click();
   await page.waitForFunction(()=>window.fixture.calls.some(c=>c.name==='stripe-connect-onboarding'&&c.args.body.school_id==='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'));
   await page.getByText(/Nessun merchant Stripe TEST associato/).waitFor();
   // Exercise same-document SPA history through the DOM History API. A driver
   // document-navigation lifecycle is not part of this application transition.
   await page.evaluate(()=>history.back());await page.getByRole('heading',{name:'Scuole',exact:true}).waitFor();
   await page.evaluate(()=>history.forward());await page.getByRole('heading',{name:'Configurazione',exact:true}).waitFor();
   assert.equal(await page.getByRole('tabpanel',{name:'Catalogo',exact:true}).isVisible(),true);
   await page.getByRole('tab',{name:'Personale',exact:true}).click();
   await page.getByRole('heading',{name:'Personale della scuola'}).waitFor();
   await page.getByLabel('Email persona').fill('collega@example.invalid');
   await page.getByRole('tab',{name:'Personale',exact:true}).press('ArrowRight');
   await page.getByRole('heading',{name:'Orari settimanali'}).waitFor();
   await page.getByRole('tab',{name:'Orari e ritiri',exact:true}).press('ArrowLeft');
   assert.equal(await page.getByLabel('Email persona').inputValue(),'collega@example.invalid');
   assert.equal(await page.getByRole('tabpanel',{name:'Catalogo',exact:true}).isVisible(),false);
   if(process.env.WORKSPACE_SCREENSHOTS)await page.screenshot({path:process.env.WORKSPACE_SCREENSHOTS+'/configuration-'+name+'-'+viewport.width+'.png',fullPage:false,animations:'disabled'});
   if(viewport.width<1024){
    await page.getByRole('button',{name:'Altro',exact:true}).click();
    await page.locator('#workspace-more-items').getByRole('link',{name:'Nuova scuola',exact:true}).click();
   }else await page.locator('#app-desktop-nav').getByRole('link',{name:'Nuova scuola',exact:true}).click();
   await page.locator('.onboarding-layout').waitFor();
   assert.equal(await page.locator('#workflow-center').isVisible(),true);
   assert.equal(await page.locator('#workflow-center').getByRole('heading',{name:'Grandi ordini'}).count(),0);
   await page.getByLabel('Nome della scuola',{exact:true}).fill('La nuova scuola');
   if(process.env.WORKSPACE_SCREENSHOTS)await page.screenshot({path:process.env.WORKSPACE_SCREENSHOTS+'/onboarding-'+name+'-'+viewport.width+'.png',fullPage:false,animations:'disabled'});
   await page.getByRole('button',{name:'Passa al tema scuro'}).click();
   assert.equal(await page.locator('html').getAttribute('data-theme'),'dark');
   if(process.env.WORKSPACE_SCREENSHOTS)await page.screenshot({path:process.env.WORKSPACE_SCREENSHOTS+'/dark-'+name+'-'+viewport.width+'.png',fullPage:false,animations:'disabled'});
   assert.equal(await page.getByLabel('Nome della scuola',{exact:true}).inputValue(),'La nuova scuola');
   const width=await page.evaluate(()=>({scroll:document.documentElement.scrollWidth,viewport:innerWidth}));assert.ok(width.scroll<=width.viewport+3,JSON.stringify(width));
   await page.evaluate(()=>window.fixture.customer());
   await page.waitForFunction(()=>document.body.dataset.activeRole==='customer');
   assert.equal(await page.locator('#platform-overview').isVisible(),false);
   assert.equal(await page.locator('#platform-directory-list').textContent(),'');
   // API failure/recovery starts with an isolated authenticated session, separate
   // from the completed navigation and role-revocation scenario above.
   await page.close();page=await browser.newPage({viewport});page.on('pageerror',error=>errors.push(error.message));
   await page.goto(origin+'/__workspace-qa');await page.locator('#platform-metrics .metric-card').first().waitFor();
   await page.evaluate(()=>{window.fixture.fail=true});await page.getByRole('button',{name:'Aggiorna',exact:true}).click();
   await page.getByText('Non riusciamo a caricare i dati',{exact:true}).waitFor();
   assert.equal(await page.locator('#platform-metrics .metric-card').count(),0);
   await page.evaluate(()=>{window.fixture.fail=false});await page.getByRole('button',{name:'Aggiorna',exact:true}).click();await page.locator('#platform-metrics .metric-card').first().waitFor();
   await page.evaluate(()=>{window.fixture.delay=200});await page.getByRole('button',{name:'Aggiorna',exact:true}).click();await page.evaluate(()=>window.fixture.logout());
   await page.waitForTimeout(300);assert.equal(await page.locator('#platform-metrics').textContent(),'');assert.equal(await page.locator('#workspace-sidebar').isVisible(),false);
   assert.equal(await page.locator('body').getAttribute('data-active-route'),null);
   assert.deepEqual(errors,[]);console.log(JSON.stringify({browser:name,viewport,result:'PASS',scenario:'workspace navigation, live metrics, search, school state, configuration tabs, onboarding, themes and role isolation'}));await page.close();
  }
  await browser.close();browser=null;
 }
}finally{await browser?.close();await server.close();}
