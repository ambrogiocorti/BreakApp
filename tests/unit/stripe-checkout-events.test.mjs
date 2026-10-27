import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyCheckoutSessionEvent } from '../../supabase/functions/stripe-webhook/checkout-events.mjs';

const base = {
  type: 'checkout.session.completed',
  account: 'acct_12345678',
  data: { object: {
    object: 'checkout.session', id: 'cs_test_abcdefghi',
    mode: 'payment', currency: 'eur', amount_total: 500,
    payment_status: 'paid', payment_intent: 'pi_123456789',
    client_reference_id: '11111111-1111-4111-8111-111111111111',
    metadata: { attempt_id: '11111111-1111-4111-8111-111111111111' }
  } }
};
const event = (type, overrides = {}) => ({
  ...base, type,
  data: { object: { ...base.data.object, ...overrides } }
});

test('Checkout sincrono pagato: contabilizzare solo da webhook', () => {
  assert.equal(classifyCheckoutSessionEvent(base).kind, 'paid');
});

test('Checkout completato ma unpaid: non contabilizzare e non sbloccare cassa', () => {
  assert.equal(classifyCheckoutSessionEvent(event('checkout.session.completed',
    { payment_status: 'unpaid' })).kind, 'pending');
});

test('Successo asincrono: stesso ledger sicuro del successo immediato', () => {
  assert.equal(classifyCheckoutSessionEvent(event(
    'checkout.session.async_payment_succeeded')).kind, 'paid');
});

test('Fallimento asincrono: chiamare riconciliazione server dedicata', () => {
  assert.equal(classifyCheckoutSessionEvent(event(
    'checkout.session.async_payment_failed', { payment_status: 'unpaid' })).kind,
  'failed');
});

test('Eventi non-Checkout non vengono elaborati', () => {
  assert.equal(classifyCheckoutSessionEvent(event('charge.succeeded')).kind, 'ignored');
});

test('Eventi incongruenti vengono respinti', () => {
  for (const candidate of [
    { amount_total: 0 }, { amount_total: 12.5 },
    { currency: 'usd' }, { payment_intent: null },
    { metadata: { attempt_id: 'different' } },
    { client_reference_id: 'not-a-uuid' },
    { id: 'cs_live_mustnotentertest' },
    { payment_status: 'unpaid' }
  ]) {
    assert.equal(classifyCheckoutSessionEvent(event(
      'checkout.session.async_payment_succeeded', candidate)).kind,
    'invalid', JSON.stringify(candidate));
  }
  assert.equal(classifyCheckoutSessionEvent({ ...base, account: 'acct_other!'}).kind,
  'invalid');
});
