import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const origin = 'https://ambrogiocorti.github.io';
const source = await readFile('supabase/functions/stripe-connect-onboarding/index.ts', 'utf8');
const isolated = source.replace(
  "import { createClient } from 'npm:@supabase/supabase-js@2.118.0';",
  'const createClient = globalThis.__createClient;'
);
const compiled = stripTypeScriptTypes(isolated);

function harness({ authenticated = true, admin = true, key = 'rk_test_TESTONLY' } = {}) {
  let handler;
  const outbound = [];
  const env = {
    SUPABASE_URL: 'https://example.supabase.co',
    SUPABASE_ANON_KEY: 'public-test-only',
    STRIPE_ONBOARDING_KEY: key
  };
  const context = {
    Response, URL, JSON,
    Deno: { env: { get: (name) => env[name] }, serve: (callback) => { handler = callback; } },
    __createClient: () => ({
      auth: { getUser: async () => authenticated ? { data: { user: { id: 'user-1' } }, error: null } : { data: {}, error: new Error('not authenticated') } },
      rpc: async () => ({ data: admin, error: null })
    }),
    fetch: async (url, options) => {
      outbound.push({ url, options });
      return new Response(JSON.stringify({ url: 'https://connect.stripe.com/setup/s/test-only' }), {
        status: 200, headers: { 'Content-Type': 'application/json' }
      });
    }
  };
  context.globalThis = context;
  runInNewContext(compiled, context);
  return {
    outbound,
    preflight: (requestOrigin = origin) => handler(new Request(
      'https://example.supabase.co/functions/v1/stripe-connect-onboarding',
      { method: 'OPTIONS', headers: {
        Origin: requestOrigin,
        'Access-Control-Request-Method': 'POST',
        'Access-Control-Request-Headers': 'authorization, x-client-info, apikey, content-type'
      } }
    )),
    invoke: (authorization = 'Bearer token', requestOrigin = origin) => handler(
      new Request('https://example.supabase.co/functions/v1/stripe-connect-onboarding', {
        method: 'POST', headers: { Authorization: authorization, Origin: requestOrigin }
      })
    )
  };
}

test('Stripe onboarding preflight permits the Supabase SDK headers on the trusted origin', async () => {
  const h = harness();
  const result = await h.preflight();
  assert.equal(result.status, 204);
  assert.equal(result.headers.get('access-control-allow-origin'), origin);
  assert.equal(result.headers.get('access-control-allow-methods'), 'POST, OPTIONS');
  const allowed = result.headers.get('access-control-allow-headers').split(',').map(v => v.trim());
  for (const header of ['authorization', 'x-client-info', 'apikey', 'content-type']) {
    assert.ok(allowed.includes(header), `Missing CORS header ${header}`);
  }
  assert.equal(h.outbound.length, 0);
  const foreign = await h.preflight('https://attacker.example');
  assert.equal(foreign.headers.get('access-control-allow-origin'), origin);
});

test('Stripe onboarding is only callable from the published BreakApp origin', async () => {
  const h = harness();
  const result = await h.invoke('Bearer token', 'https://attacker.example');
  assert.equal(result.status, 403);
  assert.equal(h.outbound.length, 0);
});

test('Stripe onboarding rejects missing or invalid sessions before API calls', async () => {
  const missing = harness();
  assert.equal((await missing.invoke('')).status, 401);
  assert.equal(missing.outbound.length, 0);
  const invalid = harness({ authenticated: false });
  assert.equal((await invalid.invoke()).status, 401);
  assert.equal(invalid.outbound.length, 0);
});

test('Stripe onboarding enforces server-attested Super Admin + AAL2 role', async () => {
  const h = harness({ admin: false });
  assert.equal((await h.invoke()).status, 403);
  assert.equal(h.outbound.length, 0);
});

test('Stripe onboarding cannot use a live or ordinary secret key', async () => {
  for (const key of ['rk_live_123456', 'sk_test_123456']) {
    const h = harness({ key });
    assert.equal((await h.invoke()).status, 503);
    assert.equal(h.outbound.length, 0);
  }
});

test('Stripe onboarding targets only the fixed test account and authenticates at the platform', async () => {
  const h = harness();
  const result = await h.invoke();
  assert.equal(result.status, 200);
  const data = await result.json();
  assert.equal(data.account_id, 'acct_1UVx5F2RLtxMJCNo');
  assert.ok(data.onboarding_url.startsWith('https://connect.stripe.com/'));
  assert.equal(h.outbound.length, 1);
  const request = h.outbound[0];
  assert.equal(request.url, 'https://api.stripe.com/v2/core/account_links');
  assert.equal(request.options.headers['Stripe-Version'], '2026-09-30.preview');
  assert.equal(request.options.headers['Stripe-Account'], undefined);
  const body = JSON.parse(request.options.body);
  assert.equal(body.account, 'acct_1UVx5F2RLtxMJCNo');
  assert.equal(body.use_case.type, 'account_onboarding');
  assert.equal(body.use_case.account_onboarding.collection_options.fields, 'eventually_due');
  assert.equal(body.use_case.account_onboarding.return_url, origin + '/BreakApp/#platform-configuration');
});
