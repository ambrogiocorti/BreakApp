// Pure, testable validation of the signed Stripe Checkout event payload.
// Signature verification and the TEST-mode restriction happen in index.ts.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ACCOUNT = /^acct_[A-Za-z0-9]+$/;
const SESSION = /^cs_test_[A-Za-z0-9]+$/;
const INTENT = /^pi_[A-Za-z0-9]+$/;

const CHECKOUT_TYPES = new Set([
  'checkout.session.completed',
  'checkout.session.async_payment_succeeded',
  'checkout.session.async_payment_failed'
]);

export function classifyCheckoutSessionEvent(event) {
  if (!CHECKOUT_TYPES.has(event?.type)) return { kind: 'ignored' };
  const session = event?.data?.object;
  if (!session || session.object !== 'checkout.session' ||
      session.mode !== 'payment' || !SESSION.test(session.id ?? '') ||
      !ACCOUNT.test(event.account ?? '') ||
      !UUID.test(session.client_reference_id ?? '') ||
      session.metadata?.attempt_id !== session.client_reference_id ||
      session.currency !== 'eur' ||
      !Number.isSafeInteger(session.amount_total) || session.amount_total <= 0) {
    return { kind: 'invalid' };
  }

  if (event.type === 'checkout.session.completed' &&
      session.payment_status === 'unpaid') {
    // A delayed method was started, NOT settled. Retain the cash lock.
    return { kind: 'pending', session };
  }

  if (!INTENT.test(session.payment_intent ?? '')) return { kind: 'invalid' };
  if (event.type === 'checkout.session.async_payment_failed' &&
      session.payment_status === 'unpaid') return { kind: 'failed', session };
  if (event.type !== 'checkout.session.async_payment_failed' &&
      session.payment_status === 'paid') return { kind: 'paid', session };
  return { kind: 'invalid' };
}
