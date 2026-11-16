import test from 'node:test';
import assert from 'node:assert/strict';
import {isInternalAdminEmail,oauthRequest,registerWithPassword,readOAuthProviders,oauthReturnError} from '../../src/js/features/auth/sign-in.js';
import {createAdminRegistrationHandler} from '../../supabase/functions/admin-registration/handler.mjs';

test('email exception matches only the exact internal domain',()=>{
 for(const email of ['a@admin.breakapp.it',' A@ADMIN.BREAKAPP.IT '])assert.equal(isInternalAdminEmail(email),true);
 for(const email of ['a@breakapp.it','a@sub.admin.breakapp.it','a@admin.breakapp.it.evil.test','a@eviladmin.breakapp.it','a@@admin.breakapp.it','a @admin.breakapp.it',null])assert.equal(isInternalAdminEmail(email),false);
});
test('Google and Microsoft requests use the published callback, account choice and required email scope',()=>{
 const redirect='https://ambrogiocorti.github.io/BreakApp/';
 assert.deepEqual(oauthRequest('azure',redirect),{provider:'azure',options:{redirectTo:redirect,scopes:'email',queryParams:{prompt:'select_account'}}});
 assert.equal(oauthRequest('google',redirect).options.scopes,'openid email profile');
 assert.throws(()=>oauthRequest('untrusted',redirect));
});
test('ordinary signup preserves email confirmation; admin self-registration is removed',async()=>{
 const calls=[],client={auth:{async signUp(args){calls.push(['signup',args]);return {data:{session:null}}},async signInWithPassword(args){calls.push(['signin',args]);return {data:{session:{user:{id:'user'}}}}}},functions:{async invoke(name,args){calls.push([name,args]);return {data:{ok:true}}}}};
 await registerWithPassword(client,{email:'person@example.invalid',password:'fixture-pass'},'https://example.invalid/');
 assert.equal(calls[0][0],'signup');assert.equal(calls[0][1].options.emailRedirectTo,'https://example.invalid/');
 calls.length=0;const result=await registerWithPassword(client,{email:'admin@admin.breakapp.it',password:'fixture-pass'},'https://example.invalid/');
 assert.equal(calls.length,0);assert.match(result.error.message,/Super Admin/);
});
test('an internal admin email never reaches public signup, sign-in or any function',async()=>{
 let touched=false;const client={auth:{async signUp(){touched=true;return{}},async signInWithPassword(){touched=true;return{}}},functions:{async invoke(){touched=true;return{data:{ok:true}}}}};
 const result=await registerWithPassword(client,{email:'x@admin.breakapp.it',password:'fixture-pass'},'https://example.invalid/');
 assert.equal(touched,false);assert.ok(result.error);assert.equal(result.data,null);
});
test('provider availability is read without session credentials and errors remain explicit',async()=>{
 const state=await readOAuthProviders({url:'https://project.example.invalid',publishableKey:'public'},async(url,options)=>{assert.equal(url.href,'https://project.example.invalid/auth/v1/settings');assert.equal(options.credentials,'omit');return new Response(JSON.stringify({external:{google:true,azure:false}}));});
 assert.deepEqual(state,{google:true,azure:false});
 await assert.rejects(()=>readOAuthProviders({url:'https://project.example.invalid',publishableKey:'public'},async()=>new Response('{}',{status:503})));
 assert.match(oauthReturnError({search:'?error=access_denied&error_description=untrusted',hash:''}),/annullato/);
 assert.equal(oauthReturnError({search:'',hash:'#platform-overview'}),null);
});

function disabledRequest(method='POST',body){
 const handler=createAdminRegistrationHandler();
 return handler(new Request('https://project.example.invalid/functions/v1/admin-registration',{method,headers:{'content-type':'application/json','x-forwarded-for':'192.0.2.5',apikey:'fixture-public-key'},body:body===undefined?undefined:JSON.stringify(body)}));
}
test('admin-registration endpoint is disabled and creates no account',async()=>{
 const r=await disabledRequest('POST',{email:'a@admin.breakapp.it',password:'fixture-pass',app_metadata:{role:'platform_admin'}});
 assert.equal(r.status,410);
 const detail=await r.json();assert.match(detail.error,/Super Admin/);
});
test('disabled admin-registration answers preflight and refuses every method and body',async()=>{
 assert.equal((await createAdminRegistrationHandler()(new Request('https://example.invalid/',{method:'OPTIONS'}))).status,200);
 assert.equal((await disabledRequest('GET')).status,410);
 assert.equal((await disabledRequest('POST',{email:'a@example.invalid',password:'fixture-pass'})).status,410);
 assert.equal((await disabledRequest('POST',{email:'a@admin.breakapp.it',password:'x'.repeat(5000)})).status,410);
});
