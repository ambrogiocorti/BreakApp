import test from 'node:test';
import assert from 'node:assert/strict';
import {approvalLabel,ticketLabel,reopenLabel,membershipLabel,paymentLabel,changeKindLabel,changeStateLabel} from '../../src/js/core/status-labels.js';
import {orderStatusLabel} from '../../src/js/features/orders/staff-board.js';

test('approval and support states are readable without changing their meaning',()=>{
  assert.equal(approvalLabel('queued'),'In coda');
  assert.equal(approvalLabel('awaiting_reschedule'),'In attesa di una nuova fascia');
  assert.equal(ticketLabel('awaiting_customer'),'In attesa di risposta');
  assert.equal(reopenLabel('denied'),'Rifiutata');
  assert.equal(membershipLabel('suspended'),'Sospeso');
  assert.equal(changeKindLabel('substitution'),'Sostituzione');
  assert.equal(changeStateLabel('customer_pending'),'In attesa del cliente');
  assert.equal(orderStatusLabel('approval_active'),'In valutazione dal bar');
});

test('payment and refund labels never call pending or failed transactions completed',()=>{
  assert.equal(paymentLabel('pending'),'In attesa');
  assert.equal(paymentLabel('processing'),'In elaborazione');
  assert.equal(paymentLabel('failed'),'Non riuscito');
  assert.equal(paymentLabel('succeeded'),'Completato');
  assert.equal(paymentLabel('unexpected'),'Stato da verificare');
});
