import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { releaseAbandonedCheckout } from '../../src/js/features/orders/checkout-release.js';
import { counterError } from '../../src/js/features/orders/counter-flow.js';

const fn=await readFile('supabase/functions/stripe-checkout-cancel/index.ts','utf8');
const order={id:'o1',display_no:19};
const client=(open,invoke={data:{status:'cancelled'}})=>{
  const calls=[];
  return {calls,rpc:async(name)=>{calls.push(name);return {data:open};},
    functions:{invoke:async(name,opts)=>{calls.push(name+':'+opts.body.order_id);return typeof invoke==='function'?invoke():invoke;}}};
};
const fast={retries:2,delay:1};

test('no open card payment: cash goes ahead without questions',async()=>{
  const c=client({open:false});
  assert.deepEqual(await releaseAbandonedCheckout(c,order,fast),{state:'free'});
  assert.deepEqual(c.calls,['staff_open_checkout']);
});

test('abandoned card payment is cancelled on Stripe automatically, no question',async()=>{
  const c=client({open:true,status:'requires_action',amount_cents:1820});
  assert.deepEqual(await releaseAbandonedCheckout(c,order,fast),{state:'free'});
  assert.deepEqual(c.calls,['staff_open_checkout','stripe-checkout-cancel:o1']);
});

test('customer paid with card meanwhile: deliver without collecting again',async()=>{
  const paid=client({open:true,status:'requires_action'},{data:{error:'Il cliente ha già completato il pagamento con carta'}});
  assert.deepEqual(await releaseAbandonedCheckout(paid,order,fast),{state:'paid'});
});

test('card payment really in progress or just opened: plain words, automatic retries',async()=>{
  const busy=await releaseAbandonedCheckout(client({open:true,status:'processing'}),order,fast);
  assert.equal(busy.state,'wait');assert.match(busy.message,/#19: il cliente sta pagando con carta/);
  let tries=0;
  const fresh=client({open:true,status:'initiated'},()=>(++tries<3?{data:{error:'Pagamento con carta appena avviato: riprova tra qualche minuto'}}:{data:{status:'cancelled'}}));
  assert.deepEqual(await releaseAbandonedCheckout(fresh,order,fast),{state:'free'});
  assert.equal(tries,3);
});

test('no technical checkout wording reaches the counter',()=>{
  const text=counterError(new Error('Checkout in corso: attendi il risultato firmato prima di modificare o incassare'));
  assert.doesNotMatch(text,/checkout|firmato/i);
  assert.match(text,/sta pagando con carta/);
});

test('edge function expires the session on Stripe and closes only unpaid expired sessions',()=>{
  assert.match(fn,/staff_checkout_to_cancel/);
  assert.match(fn,/\/expire'/);
  assert.match(fn,/s\.status!=='expired'\|\|s\.payment_status!=='unpaid'/);
  assert.match(fn,/cancel_abandoned_checkout/);
  assert.doesNotMatch(fn,/console\.log/);
});
