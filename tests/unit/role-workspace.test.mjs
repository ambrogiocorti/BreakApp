import test from 'node:test';
import assert from 'node:assert/strict';
import {allowedRoute,contextsFromMemberships,chooseInitialContext} from '../../src/js/features/shell/workspace.js';
const a='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
test('role navigation never exposes another role\'s workspace',()=>{
 assert.equal(allowedRoute('customer','warehouse-inventory'),false);
 assert.equal(allowedRoute('warehouse_manager','staff-orders-section'),false);
 assert.equal(allowedRoute('bartender','admin-catalog'),false);
 assert.equal(allowedRoute('school_admin','admin-catalog'),true);
 assert.equal(allowedRoute('customer','orders'),true);
 assert.equal(allowedRoute('platform_admin','platform-overview'),true);
});
test('contexts are derived from returned memberships not a local claimed role',()=>{
 const ctx=contextsFromMemberships([
  {school_id:a,role_assignments:[{role_code:'warehouse_manager'},{role_code:'school_admin'}]}
 ],[{id:a,name:'School A'}],false,false);
 assert.equal(ctx.length,3);
 assert.equal(ctx.find(x=>x.role==='warehouse_manager').verified,true);
 assert.equal(ctx.find(x=>x.role==='school_admin').verified,false);
 assert.equal(ctx.find(x=>x.role==='customer').verified,true);
});
test('last valid context is restored; invalid stored value cannot confer privileges',()=>{
 const ctx=contextsFromMemberships([], [{id:a,name:'School A'}],true,false);
 assert.equal(chooseInitialContext(ctx,a+':school_admin').role,'customer');
 assert.equal(chooseInitialContext(ctx,a+':customer').role,'customer');
});
test('platform admin role only added after verified server result',()=>{
 const no=contextsFromMemberships([],[],true,false);
 const yes=contextsFromMemberships([],[],true,true);
 assert.equal(no.some(x=>x.role==='platform_admin'),false);
 assert.equal(yes[0].verified,true);
});
