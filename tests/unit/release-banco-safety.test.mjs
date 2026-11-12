import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const orders=await readFile('src/js/features/orders/orders.js','utf8');

test('P0: active Banco orders are queried independently of completed history',()=>{
  assert.match(orders,/const active=\['confirmed','preparing','ready'\]/);
  assert.match(orders,/const closed=\['delivered','no_show','cancelled'\]/);
  assert.match(orders,/\.in\('school_id',schools\)\.in\('status',statuses\)/);
  assert.match(orders,/\.range\(offset,offset\+STAFF_PAGE_SIZE-1\)/);
  assert.match(orders,/count:'exact'/);
  assert.match(orders,/orders\.push\(order\)/);
  assert.match(orders,/omitted>0/);
  assert.doesNotMatch(orders,/\.order\('created_at',\{ascending:false\}\)\.limit\(500\)/);
});

test('P0: stale staff role checks and old sessions cannot restore private order data',()=>{
  assert.match(orders,/const attempt=\+\+staffAuthVersion,actor=user\?\.id/);
  assert.match(orders,/attempt!==staffAuthVersion\|\|user\?\.id!==actor/);
  assert.match(orders,/staffAuthVersion\+\+;/);
  assert.match(orders,/staffSchools=\[\];staffOrders=\[\]/);
  assert.match(orders,/if\(attempt===staffAuthVersion&&user\?\.id===actor&&staffSchools\.length\)/);
});

test('P0: an operator selecting archive changes the server query, not only local filters',()=>{
  assert.match(orders,/staffVisibilityFilter\.addEventListener\('change',\(\)=>\{void fetchStaffOrders\(\);\}\)/);
  assert.match(orders,/visibility==='active'\?\[active\]:visibility==='closed'\?\[closed\]:\[active,closed\]/);
});
