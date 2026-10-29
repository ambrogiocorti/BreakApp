import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const functions = [
  'stripe-checkout-individual',
  'stripe-checkout-group',
  'stripe-full-refund',
  'group-refund-dispatch',
];

test('Stripe payment Edge Functions accept restricted sandbox keys without allowing live keys', () => {
  for (const name of functions) {
    const code = readFileSync(new URL(`../../supabase/functions/${name}/index.ts`, import.meta.url), 'utf8');
    assert.match(code, /\^\[sr\]k_test_\[A-Za-z0-9\]\+\$/i, `${name} must limit credentials to sandbox keys`);
    assert.doesNotMatch(code, /startsWith\('sk_test_'\)/, `${name} must not exclude restricted test keys`);
  }
});
