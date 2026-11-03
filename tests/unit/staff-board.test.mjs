import test from 'node:test';
import assert from 'node:assert/strict';
import {ORDER_STATUS,orderStatusLabel,slotKey,slotLabel,
  availableSlots,boardOrders,productionTotals} from '../../src/js/features/orders/staff-board.js';

const items=(a,b)=>[{product_name:'Panino',quantity:a},{product_name:'Acqua',quantity:b}];
const at=(status,n,date='2026-11-03',time='09:55:00',contents=items(1,1))=>({
  id:String(n),display_no:n,status,
  pickup_windows:{service_date:date,starts_at:time},
  order_items:contents
});
test('no raw English status reaches the customer or bartender',()=>{
  for(const status of Object.keys(ORDER_STATUS)){
    assert.notEqual(orderStatusLabel(status),status);
  }
  assert.equal(orderStatusLabel('ready'),'Pronto al ritiro');
  assert.equal(orderStatusLabel('unknown'),'Stato da verificare');
});
test('slots are stable and ordered by date, then clock',()=>{
  const orders=[at('confirmed',3,'2026-11-04','10:00:00'),at('ready',2),
    at('preparing',1)];
  assert.deepEqual(availableSlots(orders).map(x=>x.key),[
    '2026-11-03|09:55','2026-11-04|10:00'
  ]);
  assert.match(slotLabel(orders[1]),/9:55/);
  assert.equal(slotKey({}),'unknown');
});
test('active board does not mix completed orders and sorts work by pickup slot',()=>{
  const orders=[
    at('delivered',4),at('preparing',3,'2026-11-04'),at('ready',1),
    at('confirmed',5,'2026-11-04'),at('confirmed',2)
  ];
  const active=boardOrders(orders);
  assert.deepEqual(active.map(x=>x.orders.length),[2,1,1,0]);
  assert.deepEqual(active[0].orders.map(x=>x.display_no),[2,5]);
  const closed=boardOrders(orders,{visibility:'closed'});
  assert.equal(closed[3].orders.length,1);
  const slot=boardOrders(orders,{slot:'2026-11-04|10:00'});
  assert.equal(slot.reduce((n,x)=>n+x.orders.length,0),0);
});
test('production quantities exclude already ready, delivered and cancelled orders',()=>{
  const orders=[at('confirmed',1),at('preparing',2,'2026-11-03','09:55:00',items(2,3)),
    at('ready',3,'2026-11-03','09:55:00',items(100,100)),
    at('cancelled',4,'2026-11-03','09:55:00',items(10,10))];
  assert.deepEqual(productionTotals(orders),[
    {name:'Acqua',quantity:4},{name:'Panino',quantity:3}
  ]);
  assert.deepEqual(productionTotals(orders,{slot:'2026-11-04|09:55'}),[]);
});
test('board search matches order number or item without changing server data',()=>{
  const orders=[at('confirmed',123),at('ready',456)];
  assert.equal(boardOrders(orders,{search:'123'})[0].orders.length,1);
  assert.equal(boardOrders(orders,{search:'panino'})[2].orders.length,1);
});
