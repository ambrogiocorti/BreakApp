import { chromium, firefox, webkit } from 'playwright';
const site=process.env.SMOKE_URL||'http://127.0.0.1:4173/BreakApp/';
const errors=[];
for (const [name,engine] of Object.entries({chromium,firefox,webkit}).filter(([n])=>!process.env.E2E_BROWSERS||process.env.E2E_BROWSERS.split(',').includes(n))) {
  const browser=await engine.launch({headless:true});
  for(const viewport of [{width:1440,height:900},{width:390,height:844}]){
    const page=await browser.newPage({viewport});
    const failures=[];
    page.on('pageerror',e=>failures.push(e.message));
    page.on('console',message=>{if(/Content.Security.Policy/i.test(message.text()))failures.push('CSP violation: '+message.text());});
    page.on('requestfailed',request=>{
      if(new URL(request.url()).origin===new URL(site).origin&&['script','stylesheet'].includes(request.resourceType()))
        failures.push('asset failed: '+request.url());
    });
    page.on('response',response=>{
      if(new URL(response.url()).origin===new URL(site).origin&&response.request().resourceType()==='script'&&
        !/javascript/.test(response.headers()['content-type']||''))failures.push('wrong script content type: '+response.url());
    });
    const response=await page.goto(site,{waitUntil:'domcontentloaded',timeout:30000});
    try{
      await page.waitForFunction(()=>document.body.hasAttribute('data-authenticated'),null,{timeout:15000});
    }catch{failures.push('application JavaScript did not initialize');}
    if(!response?.ok())failures.push('HTTP '+response?.status());
    const pathname=new URL(page.url()).pathname;
    if(pathname!=='/BreakApp/')failures.push('wrong base path '+pathname);
    const doc=await page.locator('body').innerText();
    if(!/accedi|accesso|login/i.test(doc))failures.push('login not present');
    const manifest=await page.locator('link[rel="manifest"]').getAttribute('href');
    if(!manifest?.includes('/BreakApp/manifest.webmanifest'))failures.push('incorrect manifest path: '+manifest);
    const csp=await page.locator('meta[http-equiv="Content-Security-Policy"]').getAttribute('content').catch(()=>null);
    if(!csp||!/script-src 'self'/.test(csp)||!/object-src 'none'/.test(csp))failures.push('missing Content-Security-Policy meta');
    const main=await page.locator('main').count();
    if(!main)failures.push('missing main landmark');
    const width=await page.evaluate(()=>({scroll:document.documentElement.scrollWidth,viewport:innerWidth}));
    if(width.scroll>width.viewport+4)failures.push('horizontal overflow '+JSON.stringify(width));
    if(process.env.WORKSPACE_SCREENSHOTS){
      const screenshotFile=process.env.WORKSPACE_SCREENSHOTS+'/login-'+name+'-'+viewport.width+'.png';
      // caret:'initial': con 'hide' Playwright inserisce un <style> che la CSP (giustamente) blocca in WebKit.
      await page.screenshot({path:screenshotFile,animations:'disabled',caret:'initial',fullPage:false});
    }
    if(failures.length)errors.push({name,viewport,failures});
    console.log(JSON.stringify({browser:name,viewport,result:failures.length?'FAIL':'PASS',failures}));
    await page.close();
  }
  await browser.close();
}
if(errors.length){console.error(JSON.stringify(errors,null,2));process.exitCode=1;}
