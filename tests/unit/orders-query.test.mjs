import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('customer order history does not embed schools from orders (no direct foreign key)',()=>{
  const src=readFileSync(new URL('../../src/js/features/orders/orders.js',import.meta.url),'utf8');
  const query=src.slice(src.indexOf("client.from('orders')"),src.indexOf(".eq('customer_id',user.id)"));
  assert.doesNotMatch(query,/schools\(/);
  assert.match(src,/from\('schools'\)\.select\('id,counter_discount_bps'\)/);
});
