import test from 'node:test';
import assert from 'node:assert/strict';
import { readSupabaseConfig } from '../../src/js/core/config.js';

test('ambiente privo di credenziali pubbliche non attiva il login', () => {
  assert.equal(readSupabaseConfig({}).configured, false);
});

test('non accetta una secret key lato client', () => {
  const config = readSupabaseConfig({
    VITE_SUPABASE_URL: 'https://sample.supabase.co',
    VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_secret_do_not_expose'
  });
  assert.equal(config.configured, false);
});

test('accetta URL HTTPS e chiave pubblicabile', () => {
  const config = readSupabaseConfig({
    VITE_SUPABASE_URL: 'https://sample.supabase.co/',
    VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test_value'
  });
  assert.equal(config.configured, true);
  assert.equal(config.url, 'https://sample.supabase.co');
});

test('rifiuta URL con credenziali incluse', () => {
  const config = readSupabaseConfig({
    VITE_SUPABASE_URL: 'https://user:pass@sample.supabase.co',
    VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test_value'
  });
  assert.equal(config.configured, false);
});
