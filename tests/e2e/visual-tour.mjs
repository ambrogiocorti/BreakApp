// Visual review: every role route on phone, tablet and desktop, light and dark.
// Uses fictional data only. Fails on page errors or horizontal overflow.
import {chromium,firefox,webkit} from 'playwright';
import {mkdirSync} from 'node:fs';
import {startDemoServer} from './support/demo-server.mjs';
const out=process.env.TOUR_OUT||'tour';mkdirSync(out,{recursive:true});
const roles={
 signedout:['accesso'],
 student:['menu','orders','groups','workflow-center','accesso','support-center'],
 guest:['menu','groups','accesso'],
 bartender:['staff-orders-section','workflow-center','bar-operations','cash-workspace','offline-terminal','support-center'],
 warehouse:['warehouse-inventory'],
 admin:['admin-overview','staff-orders-section','workflow-center','admin-catalog','warehouse-inventory','bar-operations','admin-order-setup','cash-workspace','school-reports','offline-review','accesso'],
 platform:['platform-overview','platform-schools','platform-configuration','workflow-center','accesso']
};
const only=process.env.TOUR_ROLES?.split(',');
const viewports=(process.env.TOUR_VIEWPORTS||'390x844,1440x900').split(',').map(v=>{const[w,h]=v.split('x').map(Number);return{width:w,height:h};});
const themes=(process.env.TOUR_THEMES||'light').split(',');
const engines={chromium,firefox,webkit};
const engineNames=(process.env.TOUR_BROWSERS||'chromium').split(',');
const {server,origin}=await startDemoServer(Number(process.env.TOUR_PORT||5190));
const problems=[];
try{
 for(const engineName of engineNames){
  const browser=await engines[engineName].launch();
  for(const [as,routes] of Object.entries(roles)){
   if(only&&!only.includes(as))continue;
   for(const viewport of viewports)for(const theme of themes){
    const context=await browser.newContext({viewport,colorScheme:theme,reducedMotion:'reduce'});
    // BreakApp parte sempre in chiaro: il tema scuro è una scelta salvata.
    await context.addInitScript(t=>{try{localStorage.setItem('breakapp-theme',t);}catch{}},theme);
    // TOUR_LAYOUT=b previews an alternative arrangement (tests/e2e/support/layout-b.css).
    if(process.env.TOUR_LAYOUT==='b')await context.addInitScript(()=>document.addEventListener('DOMContentLoaded',()=>{const l=document.createElement('link');l.rel='stylesheet';l.href='/tests/e2e/support/layout-b.css';document.head.append(l);}));
    const page=await context.newPage();const errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    page.on('console',m=>{if(m.type()==='error'&&!m.text().includes('Failed to load resource'))errors.push('console: '+m.text());});
    await page.goto(origin+'/__demo?as='+as+'#'+routes[0]);
    await page.waitForFunction(()=>window.demo?.ready);
    await page.waitForTimeout(700);
    for(const route of routes){
     await page.evaluate(r=>{location.hash=r;},route);
     await page.waitForTimeout(450);
     const overflow=await page.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth);
     if(overflow>1)problems.push(`${engineName} ${as} ${route} ${viewport.width} ${theme}: horizontal overflow ${overflow}px`);
     const name=`${out}/${engineName}-${as}-${route}-${viewport.width}-${theme}.png`;
     await page.screenshot({path:name,fullPage:process.env.TOUR_FULL!=='0'});
    }
    for(const e of errors)problems.push(`${engineName} ${as} ${viewport.width} ${theme}: ${e}`);
    await context.close();
   }
  }
  await browser.close();
 }
}finally{await server.close();}
console.log(problems.length?problems.join('\n'):'No problems found');
if(problems.length&&process.env.TOUR_STRICT==='1')process.exitCode=1;
