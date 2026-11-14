import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { releaseAbandonedCheckout, abandonedCheckoutQuestion } from '../../src/js/features/orders/checkout-release.js';

const fn=await readFile('supabase/functions/stripe-checkout-cancel/index.ts','utf8');
const order={id:'o1',display_no:19};
const client=(open,invoke={data:{status:'cancelled'}})=>{
  const calls=[];
  return {calls,rpc:async(name)=>{calls.push(name);return {data:open};},
    functions:{invoke:async(name,opts)=>{calls.push(name+':'+opts.body.order_id);return invoke;}}};
};

test('no open card payment: cash goes ahead without questions',async()=>{
  const c=client({open:false});
  assert.equal(await releaseAbandonedCheckout(c,order,async()=>assert.fail('asked')),'');
  assert.deepEqual(c.calls,['staff_open_checkout']);
});

test('abandoned card payment: ask, cancel it on Stripe, then cash',async()=>{
  const c=client({open:true,status:'requires_action',amount_cents:1820});
  let question='';
  assert.equal(await releaseAbandonedCheckout(c,order,async q=>{question=q;return true;}),'');
  assert.match(question,/#19.*18,20.*non potrà più pagare online/);
  assert.deepEqual(c.calls,['staff_open_checkout','stripe-checkout-cancel:o1']);
});

test('declined, processing or already paid: no cash collection',async()=>{
  assert.match(await releaseAbandonedCheckout(client({open:true,status:'requires_action'}),order,async()=>false),/ancora aperto/);
  assert.match(await releaseAbandonedCheckout(client({open:true,status:'processing'}),order,async()=>true),/in elaborazione/);
  const paid=client({open:true,status:'requires_action'},{data:{error:'Il cliente ha già completato il pagamento con carta'}});
  assert.match(await releaseAbandonedCheckout(paid,order,async()=>true),/già completato/);
  assert.match(abandonedCheckoutQuestion(5,0),/#5: il cliente ha aperto/);
});

test('edge function expires the session on Stripe and closes only unpaid expired sessions',()=>{
  assert.match(fn,/staff_checkout_to_cancel/);
  assert.match(fn,/\/expire'/);
  assert.match(fn,/s\.status!=='expired'\|\|s\.payment_status!=='unpaid'/);
  assert.match(fn,/cancel_abandoned_checkout/);
  assert.doesNotMatch(fn,/console\.log/);
});
