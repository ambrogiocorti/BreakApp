import test from 'node:test';
import assert from 'node:assert/strict';
import {shownGroupStatus,finalOrderStatus} from '../../src/js/features/groups/groups.js';

test('after confirmation the group tag shows the real order status', ()=>{
  assert.equal(shownGroupStatus('confirmed','delivered'),'delivered');
  assert.equal(shownGroupStatus('confirmed','preparing'),'preparing');
  assert.equal(shownGroupStatus('confirmed','ready'),'ready');
  assert.equal(shownGroupStatus('confirmed','cancelled'),'cancelled');
  // Without an order (still loading or not visible) the group status stays.
  assert.equal(shownGroupStatus('confirmed',undefined),'confirmed');
  // Draft, expired or cancelled groups never borrow an order status.
  assert.equal(shownGroupStatus('draft','delivered'),'draft');
  assert.equal(shownGroupStatus('expired',undefined),'expired');
});

test('only closed orders stop the live refresh', ()=>{
  for(const s of ['delivered','cancelled','no_show'])assert.equal(finalOrderStatus(s),true);
  for(const s of ['confirmed','preparing','ready'])assert.equal(finalOrderStatus(s),false);
});
