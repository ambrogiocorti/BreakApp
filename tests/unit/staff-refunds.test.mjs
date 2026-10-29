import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const orders = await readFile('src/js/features/orders/orders.js','utf8');
const html = await readFile('index.html','utf8');
const pilot = await readFile('src/js/features/shell/platform-pilot.js','utf8');
const migration = await readFile('supabase/migrations/20261029191506_allow_bartender_individual_refund.sql','utf8');

test('refunds are started from a selected staff order, without manual UUID',()=>{
  assert.match(html,/id="staff-refund-dialog"/);
  assert.match(html,/id="staff-refund-confirm"/);
  assert.match(orders,/Rimborsa ordine numero/);
  assert.match(orders,/request_completed_order_refund/);
  assert.match(orders,/p_kind:'individual',p_order:o.id,p_key:key/);
  assert.doesNotMatch(html,/id="pilot-refund-order"/);
  assert.doesNotMatch(pilot,/pilot-refund-form/);
});

test('only paid completed staff orders expose the refund button',()=>{
  assert.match(orders,/o.payment_status==='paid'&&\['delivered','no_show'\].includes\(o.status\)/);
  assert.match(orders,/staffSchools.includes\(o.school_id\)/);
  assert.match(orders,/stripeRefundKeys.get\(o.id\)\|\|crypto.randomUUID\(\)/);
});

test('database checks tenant membership, completion state and request reason',()=>{
  assert.match(migration,/app_private.can_serve_group_bar/);
  assert.match(migration,/p_kind = 'individual'/);
  assert.match(migration,/app_private.can_manage_support_school/);
  assert.match(migration,/delivered', 'no_show'/);
  assert.match(migration,/app_private.assert_no_pending_checkout/);
  assert.match(migration,/p_key IS NULL/);
});
