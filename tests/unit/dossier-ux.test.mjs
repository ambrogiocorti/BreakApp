import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {filterPublicMenu} from '../../src/js/features/menu/utils.js';

const [html,orders,menu,base,workspace,migration]=await Promise.all([
  readFile('index.html','utf8'),
  readFile('src/js/features/orders/orders.js','utf8'),
  readFile('src/js/features/menu/menu.js','utf8'),
  readFile('src/css/components.css','utf8'),
  readFile('src/css/staff.css','utf8'),
  readFile('supabase/migrations/20261103102822_enable_rls_scoped_orders_realtime.sql','utf8')
]);

test('dossier: operational workbench has production list, workflow stages and functional controls',()=>{
  for(const id of ['staff-production-list','staff-production-total','staff-slot-filter',
    'staff-visibility-filter','staff-live-status','staff-cash-toggle']){
    assert.match(html,new RegExp('id="'+id+'"'));
  }
  assert.match(orders,/productionTotals\(scoped,/);
  assert.match(orders,/boardOrders\(scoped,/);
  assert.match(orders,/staffList\.dataset\.view=/);
  assert.match(orders,/orderStatusLabel\(o\.status\)/);
  assert.doesNotMatch(html,/Aggiorna e verifica ruolo/);
});

test('dossier: realtime and fallback subscribe to tenant-scoped orders only',()=>{
  assert.match(orders,/filter:'school_id=eq\.'\+school/);
  assert.match(orders,/postgres_changes/);
  assert.match(orders,/event:'INSERT'/);
  assert.match(orders,/event:'UPDATE'/);
  assert.match(orders,/15000/);
  assert.match(orders,/removeChannel\(channel\)/);
  assert.match(orders,/staffFetchSequence/);
  assert.match(migration,/ALTER PUBLICATION supabase_realtime ADD TABLE public\.orders/);
  assert.doesNotMatch(migration,/CREATE POLICY .* USING \(true\)/);
});

test('dossier: booking has two meaningful steps, real GPS check and labeled coupon',()=>{
  assert.match(html,/Passaggio 1 di 2/);
  assert.doesNotMatch(html,/data-step="1"/);
  assert.doesNotMatch(html,/data-step="3"/);
  assert.match(html,/id="order-window"/);
  assert.match(orders,/step===2\?['"]Passaggio 1 di 2/);
  assert.match(orders,/positionOnce\(controller\.signal,await schoolAccuracyLimit\(client,context\.schoolId\)\)/);
  assert.match(orders,/submit_promoted_order/);
  assert.match(orders,/couponLabel\.htmlFor='order-coupon'/);
});

test('dossier: compact quick-add and allergen filter never claim a certified safe product',()=>{
  assert.match(menu,/breakapp:quick-add/);
  assert.match(orders,/cartAdd\(cart,id,1\)/);
  assert.match(menu,/menu-allergen-exclude/);
  assert.match(menu,/non garantisce l’assenza/);
  assert.match(menu,/breakapp-menu-school/);
  const cats=[{id:'c',is_active:true}];
  const prods=[
    {id:'x',category_id:'c',name:'Panino',is_active:true,allergens:['gluten']},
    {id:'y',category_id:'c',name:'Acqua',is_active:true,allergens:[]}
  ];
  assert.deepEqual(filterPublicMenu(cats,prods,{excludeDeclaredAllergen:'gluten'}).map(x=>x.id),['y']);
  assert.equal(filterPublicMenu(cats,prods).length,2);
});

test('dossier: shared components and theme tokens keep operative cards readable',async()=>{
  const tokens=await readFile('src/css/tokens.css','utf8');
  const shellCss=await readFile('src/css/shell.css','utf8');
  const customer=await readFile('src/css/customer.css','utf8');
  assert.match(workspace,/\.staff-board-lane \{/);
  assert.match(workspace,/\.staff-board\[data-view="active"\] \{ grid-template-columns: repeat\(3/);
  assert.match(tokens,/--lavagna-ink/);
  assert.match(shellCss,/\.brand-symbol \{/);
  assert.match(customer,/\.menu-product-add \{/);
  assert.match(base,/\.button-primary \{/);
  assert.match(html,/ordini per fascia/i);
});

test('dossier: grouped navigation preserves every role entitlement',async()=>{
  const workspaceJs=await readFile('src/js/features/shell/workspace.js','utf8');
  const icons=await readFile('src/js/core/icons.js','utf8');
  assert.match(workspaceJs,/const NAV_GROUPS=Object\.freeze/);
  for(const name of ['OGGI','OFFERTA','FINANZE','BANCO','OPERAZIONI'])
    assert.ok(workspaceJs.includes("'"+name+"'"),'Missing nav group '+name);
  assert.match(workspaceJs,/current\.append\(linkOf\(screen\)\)/);
  assert.match(workspaceJs,/const rest=available\.filter/);
  assert.match(workspaceJs,/\['cash-workspace','Cassa','Receipt'\]/);
  assert.match(icons,/Receipt:/);
  assert.match(icons,/CloudOff:/);
  assert.match(workspaceJs,/export function allowedRoute/);
});

test('adding a product to the cart shows no "nel carrello" toast',()=>{
  assert.doesNotMatch(orders,/toast\([^)]*nel carrello/);
  assert.doesNotMatch(orders,/\btoast\b/);
  assert.match(menu,/nel carrello: /);
});
