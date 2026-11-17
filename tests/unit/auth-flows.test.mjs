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
test('ordinary signup keeps email confirmation; admin signup requires the invite code and never signs up directly',async()=>{
 const calls=[],client={auth:{async signUp(args){calls.push(['signup',args]);return {data:{session:null}}},async signInWithPassword(args){calls.push(['signin',args]);return {data:{session:{user:{id:'user'}}}}}},functions:{async invoke(name,args){calls.push([name,args]);return {data:{ok:true}}}}};
 await registerWithPassword(client,{email:'person@example.invalid',password:'fixture-pass'},'https://example.invalid/');
 assert.equal(calls[0][0],'signup');assert.equal(calls[0][1].options.emailRedirectTo,'https://example.invalid/');
 calls.length=0;const result=await registerWithPassword(client,{email:'admin@admin.breakapp.it',password:'fixture-pass'},'https://example.invalid/');
 assert.equal(calls.length,0);assert.match(result.error.message,/codice di invito/i);assert.equal(result.data,null);
});
test('a valid invite code registers the admin through the backend then signs in; it never calls signUp',async()=>{
 const calls=[],client={auth:{async signUp(args){calls.push(['signup',args]);return {data:{session:null}}},async signInWithPassword(args){calls.push(['signin',args]);return {data:{session:{user:{id:'admin'}}}}}},functions:{async invoke(name,args){calls.push([name,args]);return {data:{ok:true}}}}};
 const result=await registerWithPassword(client,{email:'admin@admin.breakapp.it',password:'fixture-pass',code:' abc-123 '},'https://example.invalid/');
 assert.deepEqual(calls.map(c=>c[0]),['admin-registration','signin']);
 assert.deepEqual(calls[0][1].body,{email:'admin@admin.breakapp.it',password:'fixture-pass',code:'abc-123'});
 assert.equal(calls[1][1].email,'admin@admin.breakapp.it');assert.ok(result.data?.session?.user);
});
test('a rejected invite code surfaces an error and never signs in',async()=>{
 const calls=[],client={auth:{async signUp(){calls.push('signup');return {}},async signInWithPassword(){calls.push('signin');return {}}},functions:{async invoke(name,args){calls.push([name,args]);return {data:null,error:{message:'forbidden'}}}}};
 const result=await registerWithPassword(client,{email:'admin@admin.breakapp.it',password:'fixture-pass',code:'nope'},'https://example.invalid/');
 assert.deepEqual(calls.map(c=>Array.isArray(c)?c[0]:c),['admin-registration']);
 assert.ok(result.error);assert.equal(result.data,null);
});
test('an internal admin email never reaches public signup or sign-in without a code',async()=>{
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

function makeEnv(overrides={}){
 const base={SUPABASE_URL:'https://project.example.invalid',SUPABASE_SERVICE_ROLE_KEY:'service-key',SUPABASE_PUBLISHABLE_KEYS:JSON.stringify({default:'fixture-public-key'})};
 const merged={...base,...overrides};
 return name=>merged[name];
}
function makeClient(opts={}){
 const calls=[];
 const client={
  rpc(name,args){calls.push([name,args]);
   if(name==='claim_admin_registration')return Promise.resolve(opts.rateLimited?{error:{message:'Troppe richieste'}}:{data:null,error:null});
   if(name==='admin_registration_invite_valid')return Promise.resolve({data:opts.inviteValid!==false,error:opts.inviteValidError||null});
   if(name==='consume_admin_registration_invite')return Promise.resolve(opts.consumeError?{data:null,error:{message:'invalid'}}:{data:{school_id:'school',role:'school_admin'},error:null});
   return Promise.resolve({data:null,error:null});},
  auth:{admin:{
   createUser(args){calls.push(['createUser',args]);return Promise.resolve(opts.createError?{data:null,error:opts.createError}:{data:{user:{id:'new-admin'}},error:null});},
   deleteUser(id){calls.push(['deleteUser',id]);return Promise.resolve({data:null,error:null});}}}
 };
 return {client,calls};
}
function handlerRequest(body,{method='POST',apikey='fixture-public-key',deps,env=makeEnv()}={}){
 const handler=createAdminRegistrationHandler(deps===undefined?{createClient:()=>makeClient().client,env}:deps);
 return handler(new Request('https://project.example.invalid/functions/v1/admin-registration',{method,headers:{'content-type':'application/json',apikey,'x-forwarded-for':'192.0.2.5'},body:body===undefined?undefined:JSON.stringify(body)}));
}

test('admin-registration answers preflight and refuses non-POST, bad key, missing code',async()=>{
 assert.equal((await handlerRequest(undefined,{method:'OPTIONS'})).status,200);
 assert.equal((await handlerRequest(undefined,{method:'GET'})).status,405);
 assert.equal((await handlerRequest({email:'a@admin.breakapp.it',password:'fixture-pass',code:'x'},{apikey:'wrong-key'})).status,401);
 assert.equal((await handlerRequest({email:'a@admin.breakapp.it',password:'fixture-pass'})).status,400);
 assert.equal((await handlerRequest({email:'a@example.invalid',password:'fixture-pass',code:'x'})).status,400);
 assert.equal((await handlerRequest({email:'a@admin.breakapp.it',password:'short',code:'x'})).status,400);
});
test('admin-registration is unavailable without backend dependencies',async()=>{
 assert.equal((await handlerRequest({email:'a@admin.breakapp.it',password:'fixture-pass',code:'x'},{deps:{}})).status,503);
 assert.equal((await handlerRequest({email:'a@admin.breakapp.it',password:'fixture-pass',code:'x'},{deps:{createClient:()=>makeClient().client,env:makeEnv({SUPABASE_SERVICE_ROLE_KEY:''})}})).status,503);
});
test('a valid invite creates the confirmed account and consumes the invite',async()=>{
 const {client,calls}=makeClient();
 const response=await createAdminRegistrationHandler({createClient:()=>client,env:makeEnv()})(new Request('https://project.example.invalid/',{method:'POST',headers:{'content-type':'application/json',apikey:'fixture-public-key','x-forwarded-for':'192.0.2.5'},body:JSON.stringify({email:'a@admin.breakapp.it',password:'fixture-pass',code:'code-1'})}));
 assert.equal(response.status,200);assert.deepEqual(await response.json(),{ok:true});
 assert.deepEqual(calls.map(c=>c[0]),['claim_admin_registration','admin_registration_invite_valid','createUser','consume_admin_registration_invite']);
 assert.equal(calls[1][1].p_email,'a@admin.breakapp.it');assert.equal(calls[2][1].email_confirm,true);
});
test('an invalid or already-used invite creates no account',async()=>{
 const {client,calls}=makeClient({inviteValid:false});
 const response=await createAdminRegistrationHandler({createClient:()=>client,env:makeEnv()})(new Request('https://project.example.invalid/',{method:'POST',headers:{'content-type':'application/json',apikey:'fixture-public-key','x-forwarded-for':'192.0.2.5'},body:JSON.stringify({email:'a@admin.breakapp.it',password:'fixture-pass',code:'bad'})}));
 assert.equal(response.status,403);
 assert.equal(calls.some(c=>c[0]==='createUser'),false);
});
test('a consume failure on a fresh account rolls it back and reports the error',async()=>{
 const {client,calls}=makeClient({consumeError:true});
 const response=await createAdminRegistrationHandler({createClient:()=>client,env:makeEnv()})(new Request('https://project.example.invalid/',{method:'POST',headers:{'content-type':'application/json',apikey:'fixture-public-key','x-forwarded-for':'192.0.2.5'},body:JSON.stringify({email:'a@admin.breakapp.it',password:'fixture-pass',code:'code-1'})}));
 assert.equal(response.status,403);
 assert.deepEqual(calls.map(c=>c[0]),['claim_admin_registration','admin_registration_invite_valid','createUser','consume_admin_registration_invite','deleteUser']);
});
test('admin-registration honours the rate limit',async()=>{
 const {client,calls}=makeClient({rateLimited:true});
 const response=await createAdminRegistrationHandler({createClient:()=>client,env:makeEnv()})(new Request('https://project.example.invalid/',{method:'POST',headers:{'content-type':'application/json',apikey:'fixture-public-key','x-forwarded-for':'192.0.2.5'},body:JSON.stringify({email:'a@admin.breakapp.it',password:'fixture-pass',code:'code-1'})}));
 assert.equal(response.status,429);
 assert.equal(calls.some(c=>c[0]==='createUser'),false);
});
