import test from 'node:test';
import assert from 'node:assert/strict';
import {contextsFromMemberships,chooseInitialContext,allowedRoute}
 from '../../src/js/features/shell/workspace.js';

const a='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const b='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const schools=[{id:a,name:'Scuola A'},{id:b,name:'Scuola B'}];
const memberships=[{school_id:a,role_assignments:[
 {role_code:'customer'},{role_code:'school_admin'}
]},{school_id:b,role_assignments:[{role_code:'bartender'}]}];

test('Super Admin is exclusively global, even with legacy school/customer memberships',()=>{
 const contexts=contextsFromMemberships(memberships,schools,true,true);
 assert.equal(contexts.length,1);
 assert.deepEqual(contexts.map(c=>c.role),['platform_admin']);
 assert.equal(contexts[0].schoolId,null);
 assert.equal(contexts[0].verified,true);
});
test('Super Admin without AAL2 is still global-only but cannot enter privileged views',()=>{
 const contexts=contextsFromMemberships(memberships,schools,false,true);
 assert.equal(contexts.length,1);
 assert.equal(contexts[0].verified,false);
 assert.equal(contexts[0].role,'platform_admin');
});
test('stale customer context in local storage never bypasses Super Admin role',()=>{
 const contexts=contextsFromMemberships(memberships,schools,true,true);
 assert.equal(chooseInitialContext(contexts,a+':customer')?.role,'platform_admin');
 assert.equal(chooseInitialContext(contexts,b+':bartender')?.role,'platform_admin');
});
test('Super Admin has no customer navigation routes',()=>{
 for(const id of ['menu','orders','support-center','warehouse-inventory',
 'staff-orders-section','admin-catalog']){
  assert.equal(allowedRoute('platform_admin',id),false,id);
 }
 assert.equal(allowedRoute('platform_admin','platform-overview'),true);
 assert.equal(allowedRoute('platform_admin','accesso'),true);
});
test('regular school users retain their existing per-school roles',()=>{
 const contexts=contextsFromMemberships(memberships,schools,true,false);
 assert.ok(contexts.some(c=>c.role==='customer'&&c.schoolId===a));
 assert.ok(contexts.some(c=>c.role==='school_admin'&&c.schoolId===a));
 assert.ok(contexts.some(c=>c.role==='bartender'&&c.schoolId===b));
 assert.equal(contexts.some(c=>c.role==='platform_admin'),false);
});
