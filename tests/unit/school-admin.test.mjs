import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {isSingleChoice} from '../../src/js/core/single-choice.js';
import {euroToCents,promotionValue,PROMOTION_KINDS} from '../../src/js/features/operations/school-admin.js';
import {allowedRoute} from '../../src/js/features/shell/workspace.js';

const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8');

test('a selector with one real option is not a choice',()=>{
 assert.equal(isSingleChoice({options:[{value:'school-1'}]}),true);
 assert.equal(isSingleChoice({options:[{value:''},{value:'school-1'}]}),true);
 assert.equal(isSingleChoice({options:[{value:'a'},{value:'b'}]}),false);
 const html=read('index.html');
 for(const id of ['groups-school','support-school','catalog-school','ops-school'])
  assert.match(html,new RegExp('<select id="'+id+'"[^>]*data-hide-single'),id);
});

test('promotion amounts are written in euro and sent in cents',()=>{
 assert.equal(euroToCents('0,50'),50);
 assert.equal(euroToCents('1.2'),120);
 assert.ok(Number.isNaN(euroToCents('-1')));
 assert.equal(promotionValue('percent','15'),15);
 assert.ok(Number.isNaN(promotionValue('percent','12,5')));
 assert.equal(promotionValue('unit_discount','0,30'),30);
 assert.ok(PROMOTION_KINDS.every(([,label])=>!/centesim/i.test(label)));
});

test('school admin has its own Staff and Promotions pages; Requests keeps only requests',()=>{
 for(const route of ['school-staff','school-promotions','admin-order-setup'])assert.equal(allowedRoute('school_admin',route),true,route);
 for(const role of ['customer','bartender','warehouse_manager'])for(const route of ['school-staff','school-promotions'])
  assert.equal(allowedRoute(role,route),false,role+' '+route);
 const completion=read('src/js/features/operations/completion-ui.js');
 assert.doesNotMatch(completion,/Coupon e bundle|renderSchoolStaffPanel|set_no_show_policy|import_school_classes/);
 const workflows=read('src/js/features/operations/workflows.js');
 assert.doesNotMatch(workflows,/set_approval_capacity/);
 const admin=read('src/js/features/operations/school-admin.js');
 for(const rpc of ['set_approval_capacity','set_no_show_policy','set_guest_class_policy','import_school_classes','save_school_promotion','list_school_promotions'])
  assert.match(admin,new RegExp("'"+rpc+"'"),rpc);
});

test('the menu shows only the student own school once it is known',async()=>{
 const {restrictToOwnSchool}=await import('../../src/js/features/menu/menu.js');
 const schools=[{id:'a',name:'A'},{id:'b',name:'B'}];
 assert.deepEqual(restrictToOwnSchool(schools,'b'),[{id:'b',name:'B'}]);
 assert.deepEqual(restrictToOwnSchool(schools,null),schools);
 assert.deepEqual(restrictToOwnSchool(schools,'gone'),schools);
 const migration=read('supabase/migrations/20261106140000_customer_single_school.sql');
 for(const table of ['orders','group_drafts','group_members'])assert.match(migration,new RegExp('before insert on public\\.'+table));
 assert.match(migration,/Puoi ordinare solo dal bar della tua scuola/);
});
