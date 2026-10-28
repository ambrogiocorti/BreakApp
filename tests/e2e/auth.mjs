import {chromium,firefox,webkit} from 'playwright';
import {createServer} from 'vite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const origin='http://127.0.0.1:5180',app=readFileSync(new URL('../../index.html',import.meta.url),'utf8');
const script=`
import '/src/css/base.css';import '/src/css/workspace.css';
import {initializeAuth} from '/src/js/features/auth/auth.js';
import {initializeTheme} from '/src/js/core/theme.js';
import {initializeAdminMfa} from '/src/js/features/auth/mfa.js';
const mode=new URLSearchParams(location.search).get('mode');
window.fixture={calls:[],totp:[{id:'primary',status:'verified'}],aal:'aal2',verified:false};
const mfa={async listFactors(){return {data:{totp:structuredClone(window.fixture.totp)}}},async getAuthenticatorAssuranceLevel(){return {data:{currentLevel:window.fixture.aal}}},async enroll(args){window.fixture.calls.push({name:'enroll',args});window.fixture.totp=[{id:'new-factor',status:'unverified'}];return {data:{id:'new-factor',totp:{qr_code:'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII='}}}},async unenroll(args){window.fixture.calls.push({name:'unenroll',args});window.fixture.totp=window.fixture.totp.filter(f=>f.id!==args.factorId);return {data:{}}},async challengeAndVerify(args){window.fixture.calls.push({name:'verify',args});window.fixture.totp=[{id:'new-factor',status:'verified'}];window.fixture.aal='aal2';return {data:{}}}};
const client={auth:{mfa,onAuthStateChange(){},async getUser(){return {data:{user:null}}},async signInWithOAuth(args){window.fixture.calls.push({name:'oauth',args});return {data:{url:'https://provider.example.invalid/'}}},async signUp(args){window.fixture.calls.push({name:'signup',args});return {data:{session:null}}},async signInWithPassword(args){window.fixture.calls.push({name:'password',args});return {data:{session:{user:{id:'new-user',email:args.email}},user:{id:'new-user',email:args.email}}}},async signOut(){return {data:{}}}},async rpc(){return {data:false}},functions:{async invoke(name,args){window.fixture.calls.push({name,args});return {data:{ok:true}}}},from(){return {select(){return this},eq(){return this},order(){return this},async then(resolve,reject){return Promise.resolve({data:[]}).then(resolve,reject)}}}};
initializeTheme();
if(mode==='mfa'){
 document.getElementById('signed-out-view').hidden=true;document.getElementById('signed-in-view').hidden=false;
 const controller=initializeAdminMfa(client,verified=>{window.fixture.verified=verified});
 window.fixture.primary=async()=>{window.fixture.totp=[];window.fixture.aal='aal1';await controller.show()};
 window.fixture.pending=async()=>{window.fixture.totp=[{id:'pending',status:'unverified'}];window.fixture.aal='aal1';await controller.show()};
 window.fixture.hide=controller.hide;await controller.show();
}else initializeAuth({configured:true,url:location.origin,publishableKey:'fixture-public-key'},(_url,_key,options)=>{window.fixture.options=options;return client});
window.fixture.ready=true;
`;
const html=app.replaceAll('%BASE_URL%','/').replace('<script type="module" src="/src/js/main.js"></script>','<script type="module">'+script+'</script>');
const server=await createServer({base:'/',server:{host:'127.0.0.1',port:5180,strictPort:true},plugins:[{name:'auth-fixture',configureServer(vite){vite.middlewares.use('/__auth-qa',(_req,res)=>{res.setHeader('Content-Type','text/html');res.end(html)});vite.middlewares.use('/auth/v1/settings',(_req,res)=>{res.setHeader('Content-Type','application/json');res.end(JSON.stringify({external:{google:true,azure:true}}))})}}]});
await server.listen();let browser;
const engines=process.env.AUTH_BROWSER==='chromium'?{chromium}:{chromium,firefox,webkit};
try{
 for(const[name,engine]of Object.entries(engines)){
  browser=await engine.launch({headless:true});
  for(const viewport of [{width:1440,height:1000},{width:390,height:844}]){
   let page=await browser.newPage({viewport});const errors=[];page.on('pageerror',e=>errors.push(e.message));
   await page.goto(origin+'/__auth-qa');await page.waitForFunction(()=>window.fixture?.ready&&document.getElementById('google-button').disabled===false);
   assert.equal(await page.evaluate(()=>window.fixture.options.auth.flowType),'pkce');
   await page.getByRole('button',{name:'Google',exact:true}).click();
   await page.waitForFunction(()=>window.fixture.calls.some(c=>c.name==='oauth'&&c.args.provider==='google'));
   await page.getByRole('button',{name:'Microsoft',exact:true}).click();
   await page.waitForFunction(()=>window.fixture.calls.some(c=>c.name==='oauth'&&c.args.provider==='azure'&&c.args.options.scopes==='email'));
   const callbacks=await page.evaluate(()=>window.fixture.calls.filter(c=>c.name==='oauth').map(c=>c.args.options.redirectTo));assert.deepEqual(callbacks,[origin+'/',origin+'/']);
   await page.getByLabel('Indirizzo email',{exact:true}).fill('normal@example.invalid');await page.getByLabel('Password',{exact:true}).fill('fixture-pass');
   await page.getByRole('button',{name:'Registrati',exact:true}).click();await page.waitForFunction(()=>window.fixture.calls.some(c=>c.name==='signup'));
   assert.equal(await page.locator('#signed-out-view').isVisible(),true);
   await page.getByLabel('Indirizzo email',{exact:true}).fill('demo@admin.breakapp.it');await page.getByRole('button',{name:'Registrati',exact:true}).click();
   await page.locator('#signed-in-view').waitFor();
   assert.deepEqual(await page.evaluate(()=>window.fixture.calls.filter(c=>['admin-registration','password'].includes(c.name)).map(c=>c.name)),['admin-registration','password']);
   assert.equal(await page.locator('#mfa-backup-button').count(),0);
   assert.deepEqual(errors,[]);await page.close();
   page=await browser.newPage({viewport});page.on('pageerror',e=>errors.push(e.message));await page.goto(origin+'/__auth-qa?mode=mfa');await page.waitForFunction(()=>window.fixture?.ready);
   assert.equal(await page.evaluate(()=>window.fixture.verified),true);assert.equal(await page.locator('#mfa-enroll-button').isVisible(),false);
   await page.evaluate(()=>document.getElementById('mfa-enroll-button').click());await page.getByText(/Il fattore esistente deve essere rimosso/).waitFor();
   assert.equal(await page.evaluate(()=>window.fixture.calls.filter(c=>c.name==='enroll').length),0);
   await page.evaluate(()=>window.fixture.pending());await page.getByRole('button',{name:'Attiva 2FA con QR',exact:true}).click();
   await page.locator('#mfa-qr-panel').waitFor();assert.deepEqual(await page.evaluate(()=>window.fixture.calls.filter(c=>['unenroll','enroll'].includes(c.name)).map(c=>c.name)),['unenroll','enroll']);
   await page.getByLabel('Codice temporaneo (6 cifre)').fill('123456');await page.getByRole('button',{name:'Verifica codice',exact:true}).click();await page.waitForFunction(()=>window.fixture.verified===true);
   assert.equal(await page.locator('#mfa-qr').getAttribute('src'),null);assert.equal(await page.locator('#mfa-backup-button').count(),0);
   const width=await page.evaluate(()=>({scroll:document.documentElement.scrollWidth,viewport:innerWidth}));assert.ok(width.scroll<=width.viewport+3,JSON.stringify(width));assert.deepEqual(errors,[]);
   console.log(JSON.stringify({browser:name,viewport,result:'PASS',scenario:'Google/Microsoft PKCE, signup domain policy, primary-only MFA and enrollment recovery'}));await page.close();
  }
  await browser.close();browser=null;
 }
}finally{await browser?.close();await server.close();}
