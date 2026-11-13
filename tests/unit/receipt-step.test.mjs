import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { receiptQuestion, pendingReceiptCents, markReceiptsIssued } from '../../src/js/features/orders/receipt-step.js';

test('receipt question names order and amount',()=>{
  assert.match(receiptQuestion(27,400),/Ordine #27: batti lo scontrino di 4,00\s€/);
  assert.match(receiptQuestion(27,400,{online:true}),/pagato online/);
});
test('pending receipt amount nets returns and survives errors',async()=>{
  assert.equal(await pendingReceiptCents({rpc:async()=>({data:{sale_cents:500,return_cents:100}})},'o'),400);
  assert.equal(await pendingReceiptCents({rpc:async()=>({error:new Error('x')})},'o'),0);
  assert.equal(await markReceiptsIssued({rpc:async()=>({data:1})},'o'),'');
  assert.match(await markReceiptsIssued({rpc:async()=>({error:new Error('x')})},'o'),/Scontrini da emettere/);
});
test('counter collection asks for the receipt before the payment and marks it after',()=>{
  const src=readFileSync(new URL('../../src/js/features/orders/orders.js',import.meta.url),'utf8');
  const fn=src.slice(src.indexOf('async function collectAndDeliver'),src.indexOf('function action('));
  assert.ok(fn.indexOf('receiptQuestion')<fn.indexOf('hai ricevuto'));
  assert.ok(fn.indexOf('record_individual_counter_payment')<fn.indexOf('markReceiptsIssued'));
});
