import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { refundReason, OTHER_REASON, REFUND_REASONS, exchangeableLines, exchangeDifference, exchangeDifferenceText,
  cashReturnQuestion, returnCashNow, cashOutcomeText } from '../../src/js/features/orders/refund-exchange.js';

const migration=await readFile('supabase/migrations/20261113180000_order_exchange_and_quick_refund.sql','utf8');

test('preset reasons are valid and «Altro» needs 8 characters',()=>{
  for(const r of REFUND_REASONS)assert.equal(refundReason(r,''),r);
  assert.equal(refundReason(OTHER_REASON,'corto'),'');
  assert.equal(refundReason(OTHER_REASON,'  Cliente allergico  '),'Cliente allergico');
});

test('exchange difference: more expensive is paid, cheaper is given back',()=>{
  assert.equal(exchangeDifference(250,400,1),150);
  assert.equal(exchangeDifference(250,100,2),-300);
  assert.equal(exchangeDifference(250,250,3),0);
  assert.match(exchangeDifferenceText(150),/paga la differenza: 1,50/);
  assert.match(exchangeDifferenceText(-300),/tornano 3,00.*come ha pagato/);
  assert.match(exchangeDifferenceText(0),/Stesso prezzo/);
  assert.deepEqual(exchangeableLines({order_items:[{product_id:'a',quantity:1,unit_cents:100},{product_name:'x',quantity:1}]}).map(l=>l.product_id),['a']);
});

test('cash is returned and recorded in one step; a closed shift leaves it pending',async()=>{
  assert.match(cashReturnQuestion(18,180),/#18.*1,80.*in contanti.*reso/);
  const calls=[];
  const ok={rpc:async(name,args)=>{calls.push(name);return name==='order_cash_refunds_to_return'?{data:[{id:'r1',amount_cents:180}]}:{data:null};}};
  assert.deepEqual(await returnCashNow(ok,'o1','Prodotto sbagliato'),{returned:180,pending:0,problem:''});
  assert.deepEqual(calls,['order_cash_refunds_to_return','confirm_cash_refund_return']);
  const closed={rpc:async name=>name==='order_cash_refunds_to_return'?{data:[{id:'r1',amount_cents:180}]}:{error:{message:'Apri il turno di cassa per registrare la restituzione fisica'}}};
  const outcome=await returnCashNow(closed,'o1','Prodotto sbagliato');
  assert.equal(outcome.pending,180);
  assert.match(cashOutcomeText(outcome),/apri il turno di cassa/);
});

test('database: exchange is staff only, on delivered paid orders, and reuses the money rules',()=>{
  assert.match(migration,/app_private\.can_serve_group_bar\(o\.school_id\)/);
  assert.match(migration,/o\.status<>'delivered' or o\.payment_status<>'paid'/);
  assert.match(migration,/insert into public\.order_additional_receipts/);
  assert.match(migration,/app_private\.refund_order_credit\('individual',o\.id,null,-v_diff/);
  assert.match(migration,/revoke all on public\.order_exchanges from public,anon,authenticated/);
});
