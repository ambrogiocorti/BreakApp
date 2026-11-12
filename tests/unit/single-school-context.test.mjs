import test from 'node:test';
import assert from 'node:assert/strict';
import {contextsFromMemberships,chooseInitialContext} from '../../src/js/features/shell/workspace.js';

const demo='00000000-0000-4000-8000-00000000000a';
const manzoni='00000000-0000-4000-8000-00000000000b';
const schools=[{id:demo,name:'DEMO BreakApp'},{id:manzoni,name:'Liceo Manzoni'}];

test('a student bound to a school never lands in another school that sorts first',()=>{
 const memberships=[{school_id:manzoni,role_assignments:[{role_code:'customer'}]}];
 const contexts=contextsFromMemberships(memberships,schools,false,false);
 assert.deepEqual(contexts.map(c=>c.key),[manzoni+':customer']);
 assert.equal(chooseInitialContext(contexts,demo+':customer').schoolId,manzoni);
});

test('a school admin before MFA only gets the admin context of their school',()=>{
 const memberships=[{school_id:demo,role_assignments:[{role_code:'school_admin'}]}];
 const contexts=contextsFromMemberships(memberships,schools,false,false);
 assert.deepEqual(contexts.map(c=>[c.key,c.verified]),[[demo+':school_admin',false]]);
 const selected=chooseInitialContext(contexts,manzoni+':customer');
 assert.equal(selected.role,'school_admin');
 assert.equal(selected.verified,false);
});

test('an account not yet bound to a school keeps the list of active schools',()=>{
 const contexts=contextsFromMemberships([],schools,false,false);
 assert.deepEqual(contexts.map(c=>c.role),['customer','customer']);
});

test('the DEMO flag travels with the context and toggles the notice',async()=>{
 const {showDemoNotice}=await import('../../src/js/features/shell/workspace.js');
 const contexts=contextsFromMemberships(
  [{school_id:demo,role_assignments:[{role_code:'customer'}]}],
  [{id:demo,name:'DEMO BreakApp',is_demo:true},{id:manzoni,name:'Liceo Manzoni'}],false,false);
 assert.equal(contexts[0].isDemo,true);
 const notice={hidden:true};const body={dataset:{}};
 const doc={body,getElementById:id=>id==='demo-notice'?notice:null};
 showDemoNotice(true,doc);
 assert.equal(notice.hidden,false);assert.equal(body.dataset.demo,'true');
 showDemoNotice(false,doc);
 assert.equal(notice.hidden,true);assert.equal('demo' in body.dataset,false);
});

test('the DEMO notice text is in the page and says no real charge happens',async()=>{
 const {readFile}=await import('node:fs/promises');
 const html=await readFile(new URL('../../index.html',import.meta.url),'utf8');
 assert.match(html,/id="demo-notice"[^>]*hidden>Ambiente dimostrativo — pagamenti di prova, nessun addebito reale\./);
});
