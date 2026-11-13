import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {weekdayList} from '../../src/js/features/orders/admin-setup.js';
const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8');
test('weekday list starts on Monday and removes duplicates',()=>{
  assert.equal(weekdayList([5,1,3,1]),'Lun, Mer, Ven');
  assert.equal(weekdayList([0,6,1]),'Lun, Sab, Dom');
});
test('admin manages weekly slots only through 2FA RPCs',()=>{
  const js=read('src/js/features/orders/admin-setup.js');
  for(const rpc of ['list_pickup_templates','add_pickup_templates','remove_pickup_template'])
    assert.match(js,new RegExp(`rpc\\('${rpc}'`));
  assert.doesNotMatch(js,/from\('pickup_window_templates'\)/);
  const html=read('index.html');
  assert.equal((html.match(/name="ops-template-day"/g)||[]).length,7);
});
test('rollover runs inside the existing per-minute maintenance and never refunds by itself',()=>{
  const sql=read('supabase/migrations/20261113130000_weekly_slots_and_pickup_rollover.sql');
  assert.match(sql,/perform app_private\.roll_over_missed_pickups\(p_clock\)/);
  const body=sql.slice(sql.indexOf('create function app_private.roll_over_missed_pickups'),sql.indexOf('do $daily$'));
  assert.doesNotMatch(body,/refund_order_credit|status='no_show'|cancel_workflow_order/);
});
