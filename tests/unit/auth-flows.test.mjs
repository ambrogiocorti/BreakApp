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
test('ordinary signup preserves email confirmation and internal signup signs in through normal Auth',async()=>{
 const calls=[],client={auth:{async signUp(args){calls.push(['signup',args]);return {data:{session:null}}},async signInWithPassword(args){calls.push(['signin',args]);return {data:{session:{user:{id:'user'}}}}}},functions:{async invoke(name,args){calls.push([name,args]);return {data:{ok:true}}}}};
 await registerWithPassword(client,{email:'person@example.invalid',password:'fixture-pass'},'https://example.invalid/');
 assert.equal(calls[0][0],'signup');assert.equal(calls[0][1].options.emailRedirectTo,'https://example.invalid/');
 calls.length=0;await registerWithPassword(client,{email:'admin@admin.breakapp.it',password:'fixture-pass'},'https://example.invalid/');
 assert.deepEqual(calls.map(c=>c[0]),['admin-registration','signin']);assert.deepEqual(Object.keys(calls[0][1].body).sort(),['email','password']);
});
test('an internal registration error never attempts to sign in or falls back to public signup',async()=>{
 let signin=false;const result=await registerWithPassword({functions:{async invoke(){return {error:{context:new Response(JSON.stringify({error:'Troppe richieste.'}))}}}},auth:{async signInWithPassword(){signin=true}}},{email:'x@admin.breakapp.it',password:'fixture-pass'},'https://example.invalid/');
 assert.equal(signin,false);assert.match(result.error.message,/Troppe richieste/);
});
test('provider availability is read without session credentials and errors remain explicit',async()=>{
 const state=await readOAuthProviders({url:'https://project.example.invalid',publishableKey:'public'},async(url,options)=>{assert.equal(url.href,'https://project.example.invalid/auth/v1/settings');assert.equal(options.credentials,'omit');return new Response(JSON.stringify({external:{google:true,azure:false}}));});
 assert.deepEqual(state,{google:true,azure:false});
 await assert.rejects(()=>readOAuthProviders({url:'https://project.example.invalid',publishableKey:'public'},async()=>new Response('{}',{status:503})));
 assert.match(oauthReturnError({search:'?error=access_denied&error_description=untrusted',hash:''}),/annullato/);
 assert.equal(oauthReturnError({search:'',hash:'#platform-overview'}),null);
});

function registrationFixture({rateError=null,createError=null}={}){
 const calls=[];const handler=createAdminRegistrationHandler({env:name=>({SUPABASE_URL:'https://project.example.invalid',SUPABASE_SERVICE_ROLE_KEY:'fixture-service-key'})[name],createClient:()=>({async rpc(name,args){calls.push({rpc:name,args});return {error:rateError}},auth:{admin:{async createUser(args){calls.push({create:args});return {data:{user:{id:'new-user'}},error:createError}}}}})});
 const request=body=>handler(new Request('https://project.example.invalid/functions/v1/admin-registration',{method:'POST',headers:{'content-type':'application/json','x-forwarded-for':'192.0.2.5'},body:JSON.stringify(body)}));return {calls,request,handler};
}
test('registration service confirms internal accounts without accepting role or metadata input',async()=>{
 const f=registrationFixture(),response=await f.request({email:' A@ADMIN.BREAKAPP.IT ',password:'fixture-pass',app_metadata:{role:'platform_admin'},user_metadata:{admin:true}});
 assert.equal(response.status,200);assert.deepEqual(await response.json(),{ok:true});
 assert.match(f.calls[0].args.p_fingerprint,/^[a-f0-9]{64}$/);assert.equal(f.calls[0].args.p_fingerprint.includes('192.0.2.5'),false);
 assert.deepEqual(f.calls[1].create,{email:'a@admin.breakapp.it',password:'fixture-pass',email_confirm:true});
});
test('registration service rejects other domains and short passwords before privileged operations',async()=>{
 const f=registrationFixture();for(const email of ['a@example.invalid','a@admin.breakapp.it.evil.test','a@sub.admin.breakapp.it'])assert.equal((await f.request({email,password:'fixture-pass'})).status,400);
 assert.equal((await f.request({email:'a@admin.breakapp.it',password:'short'})).status,400);assert.equal(f.calls.length,0);
});
test('rate limits prevent account creation; duplicate signup never overwrites the old account',async()=>{
 const limited=registrationFixture({rateError:{message:'limit'}});assert.equal((await limited.request({email:'a@admin.breakapp.it',password:'fixture-pass'})).status,429);assert.equal(limited.calls.length,1);
 const duplicate=registrationFixture({createError:{code:'email_exists'}});assert.equal((await duplicate.request({email:'a@admin.breakapp.it',password:'fixture-pass'})).status,200);assert.equal(duplicate.calls.length,2);
});
test('registration service rejects oversized or malformed requests and does not disclose errors',async()=>{
 const f=registrationFixture();assert.equal((await f.request({email:'a@admin.breakapp.it',password:'x'.repeat(5000)})).status,400);
 assert.equal((await f.handler(new Request('https://example.invalid/',{method:'GET'}))).status,405);
 const broken=registrationFixture({createError:{code:'database_error',message:'private details'}}),r=await broken.request({email:'a@admin.breakapp.it',password:'fixture-pass'});assert.equal(r.status,400);assert.doesNotMatch(await r.text(),/private details/);
});
