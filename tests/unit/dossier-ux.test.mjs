import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {filterPublicMenu} from '../../src/js/features/menu/utils.js';

const [html,orders,menu,base,workspace,migration]=await Promise.all([
  readFile('index.html','utf8'),
  readFile('src/js/features/orders/orders.js','utf8'),
  readFile('src/js/features/menu/menu.js','utf8'),
  readFile('src/css/base.css','utf8'),
  readFile('src/css/workspace.css','utf8'),
  readFile('supabase/migrations/20261103102822_enable_rls_scoped_orders_realtime.sql','utf8')
]);

test('dossier: operational workbench has production list, workflow stages and functional controls',()=>{
  for(const id of ['staff-production-list','staff-production-total','staff-slot-filter',
    'staff-visibility-filter','staff-live-status','staff-action-confirm']){
    assert.match(html,new RegExp('id="'+id+'"'));
  }
  assert.match(orders,/productionTotals\(scoped,/);
  assert.match(orders,/boardOrders\(scoped,/);
  assert.match(orders,/staffList\.dataset\.view=staffVisibilityFilter\.value/);
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
  assert.match(orders,/positionOnce\(\)/);
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

test('dossier: component isolation and theme tokens restore operative cards',()=>{
  assert.doesNotMatch(workspace,/^\.pilot-card\{padding:0;border:0;border-radius:0;/m);
  assert.match(workspace,/#platform-configuration \.pilot-grid>\.pilot-card/);
  assert.match(workspace,/\.staff-board-lane\{/);
  assert.match(workspace,/#dashboard-recent-orders \.service-list-item\{flex-direction:row/);
  assert.match(base,/--on-accent/);
  assert.match(base,/\.brand-symbol \{ display: inline-flex/);
  assert.match(base,/\.menu-product-add\{/);
  assert.match(html,/ordini per fascia/i);
});

test('dossier: navigation is grouped for school administrators without changing route entitlements',async()=>{
  const workspaceJs=await readFile('src/js/features/shell/workspace.js','utf8');
  const icons=await readFile('src/js/core/icons.js','utf8');
  assert.match(workspaceJs,/const NAV_GROUPS=Object\.freeze/);
  for(const name of ['OGGI','OFFERTA','FINANZE','BANCO','OPERAZIONI'])
    assert.ok(workspaceJs.includes("'"+name+"'"),'Missing nav group '+name);
  assert.match(workspaceJs,/nav\.append\(create\('span','workspace-nav-caption',group\)\)/);
  assert.match(workspaceJs,/\['cash-workspace','Cassa','Receipt'\]/);
  assert.match(icons,/Receipt:/);
  assert.match(icons,/CloudOff:/);
  assert.match(workspaceJs,/export function allowedRoute/);
});
