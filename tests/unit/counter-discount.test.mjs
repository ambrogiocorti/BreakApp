import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { counterDiscountPercent, counterDueCents, counterDiscountNote, counterPriceSentence } from '../../src/js/features/orders/counter-discount.js';

const euro=c=>(c/100).toFixed(2).replace('.',',')+' €';
const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8');

test('percent label is Italian and empty when there is no discount',()=>{
  assert.equal(counterDiscountPercent(500),'5');
  assert.equal(counterDiscountPercent(750),'7,5');
  assert.equal(counterDiscountPercent(0),'');
  assert.equal(counterDiscountPercent(undefined),'');
});

test('counter amount comes from the server, falling back to the full residual',()=>{
  assert.equal(counterDueCents({due_cents:250,counter_due_cents:237}),237);
  assert.equal(counterDueCents({due_cents:250}),250);
  assert.equal(counterDueCents({due_cents:0,counter_due_cents:0}),0);
});

test('barista note appears only when a discount really lowers the amount',()=>{
  assert.equal(counterDiscountNote({due_cents:250,counter_due_cents:237,counter_discount_bps:500}),' (sconto al banco del 5% già applicato)');
  assert.equal(counterDiscountNote({due_cents:250,counter_due_cents:250,counter_discount_bps:0}),'');
  assert.equal(counterDiscountNote({due_cents:0,counter_due_cents:0,counter_discount_bps:500}),'');
});

test('customer sentence matches the server rounding (half up, cents)',()=>{
  assert.equal(counterPriceSentence(250,500,euro),'Online 2,50 € · al banco 2,37 € (sconto 5%)');
  assert.equal(counterPriceSentence(1000,1000,euro),'Online 10,00 € · al banco 9,00 € (sconto 10%)');
  assert.equal(counterPriceSentence(250,0,euro),'');
  assert.equal(counterPriceSentence(1,1000,euro),'');
});

test('every counter collection prompt uses the discounted amount',()=>{
  assert.match(read('src/js/features/orders/orders.js'),/const due=counterDueCents\(balance\.data\)[^]*hai ricevuto \$\{formatEuro\(due\)\}/);
  assert.match(read('src/js/features/orders/pickup-qr.js'),/data\.due_cents=counterDueCents\(balance\.data\)/);
  assert.match(read('src/js/features/groups/group-service.js'),/cents\(counterDueCents\(data\)\)\+' dal coordinatore'/);
  assert.match(read('src/js/features/offline/terminal.js'),/o\.counter_due_cents\?\?o\.due_cents/);
});

test('admin sets the discount through the 2FA RPC, never by writing the table',()=>{
  const setup=read('src/js/features/orders/admin-setup.js');
  assert.match(setup,/rpc\('set_school_price_policy'/);
  assert.doesNotMatch(setup,/update\(\{counter_discount_bps/);
  const html=read('index.html');
  for(const value of ['none','counter_discount','price_increase'])
    assert.match(html,new RegExp(`name="ops-price-policy" value="${value}"`));
  assert.match(html,/id="ops-price-percent"[^>]*max="20"/);
});

test('migration keeps card payments at list price and rejects client access',()=>{
  const sql=read('supabase/migrations/20261112090000_counter_payment_discount.sql');
  assert.match(sql,/check \(counter_discount_bps between 0 and 1000\)/);
  assert.match(sql,/price_policy in \('none','counter_discount','price_increase'\)/);
  assert.match(sql,/\(price_policy='counter_discount' or counter_discount_bps=0\)/);
  assert.match(sql,/revoke all on public\.order_counter_discounts from public,anon,authenticated/);
  assert.doesNotMatch(sql,/begin_individual_stripe_checkout|begin_group_stripe_checkout/,'online checkout amount must not change');
});
