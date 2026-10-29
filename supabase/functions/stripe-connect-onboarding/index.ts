// Stripe Connect: bootstrap di un merchant demo in SOLO ambiente di test.
// La chiave STRIPE_ONBOARDING_KEY deve restare nei Secrets delle Edge Functions.
import { createClient } from 'npm:@supabase/supabase-js@2.118.0';

const ORIGIN = 'https://ambrogiocorti.github.io';
const RETURN_URL = ORIGIN + '/BreakApp/#platform-configuration';
// Account demo creato appositamente per il collaudo; nessun ID dal client.
const TEST_ACCOUNT = 'acct_1UVx5F2RLtxMJCNo';
const ALLOWED_HEADERS = {
  'access-control-allow-origin': ORIGIN,
  'access-control-allow-methods': 'POST, OPTIONS',
  'access-control-allow-headers': 'authorization, x-client-info, apikey, content-type, x-retry-count, traceparent, tracestate, baggage',
  'cache-control': 'no-store',
  'vary': 'Origin'
};

function respond(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...ALLOWED_HEADERS, 'content-type': 'application/json; charset=utf-8' }
  });
}

function secret(name: string) {
  return Deno.env.get(name)?.trim() ?? '';
}

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: ALLOWED_HEADERS });
  }
  if (request.method !== 'POST') return respond({ error: 'Metodo non consentito' }, 405);
  if (request.headers.get('Origin') !== ORIGIN) {
    return respond({ error: 'Origine non autorizzata' }, 403);
  }

  const token = request.headers.get('Authorization')?.replace(/^Bearer\s+/i, '').trim();
  if (!token) return respond({ error: 'Devi accedere prima di continuare' }, 401);

  try {
    const url = secret('SUPABASE_URL');
    const anonKey = secret('SUPABASE_ANON_KEY');
    if (!url || !anonKey) return respond({ error: 'Autenticazione server non disponibile' }, 503);

    const client = createClient(url, anonKey, {
      global: { headers: { Authorization: 'Bearer ' + token } },
      auth: { persistSession: false, autoRefreshToken: false }
    });
    const { data: identity, error: authError } = await client.auth.getUser(token);
    if (authError || !identity.user) {
      return respond({ error: 'Sessione non valida' }, 401);
    }

    // La RPC controlla il ruolo globale reale e richiede AAL2 (MFA).
    const { data: isAdmin, error: roleError } = await client.rpc('is_current_platform_admin');
    if (roleError || isAdmin !== true) {
      return respond({ error: 'Solo il Super Admin con 2FA può avviare Stripe' }, 403);
    }

    const stripeKey = secret('STRIPE_ONBOARDING_KEY');
    if (!/^rk_test_[A-Za-z0-9]+$/.test(stripeKey)) {
      return respond({ error: 'Chiave Stripe di test per onboarding non configurata' }, 503);
    }

    // Questo merchant demo esistente è un account Connect Standard (Accounts v1).
    // Il relativo flusso Stripe-hosted usa /v1/account_links; nessun account viene creato.
    const params = new URLSearchParams({
      account: TEST_ACCOUNT,
      type: 'account_onboarding',
      'collection_options[fields]': 'eventually_due',
      return_url: RETURN_URL,
      refresh_url: RETURN_URL
    });
    const response = await fetch('https://api.stripe.com/v1/account_links', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + stripeKey,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Stripe-Version': '2026-09-30.endive'
      },
      body: params
    });

    // Leggiamo l'errore strutturato di Stripe senza esporre dati dell'account.
    const data = await response.json().catch(() => ({})) as {
      url?: unknown;
      expires_at?: unknown;
      error?: { type?: unknown; code?: unknown }
    };
    if (!response.ok) {
      const type = typeof data.error?.type === 'string' && /^[a-z_]{1,64}$/.test(data.error.type)
        ? data.error.type : 'unknown';
      const code = typeof data.error?.code === 'string' && /^[a-z0-9_]{1,64}$/.test(data.error.code)
        ? data.error.code : 'unknown';
      const requestId = response.headers.get('request-id') || '';
      const safeRequestId = /^req_[a-zA-Z0-9]{8,64}$/.test(requestId) ? requestId : '';
      console.error('Stripe account onboarding rejected', { status: response.status, type, code, requestId: safeRequestId });
      const reason = response.status === 401
        ? 'Stripe ha rifiutato la chiave API di test. Verifica che sia valida e appartenga alla piattaforma.'
        : response.status === 403
          ? 'La chiave Stripe non è autorizzata a creare link Connect: controlla i permessi Account Links.'
          : code === 'resource_missing' || response.status === 404
            ? 'Il merchant demo indicato non è accessibile alla piattaforma Stripe usata dalla chiave.'
            : response.status === 400
              ? 'Stripe ha respinto la richiesta di onboarding: controlla parametri, modalità test e stato del merchant.'
              : 'Stripe non ha generato il link di attivazione.';
      return respond({ error: reason, stripe_status: response.status, stripe_type: type,
        stripe_code: code, ...(safeRequestId ? { stripe_request_id: safeRequestId } : {}) }, 502);
    }
    if (typeof data.url !== 'string') {
      return respond({ error: 'Stripe non ha restituito un link utilizzabile' }, 502);
    }
    const destination = new URL(data.url);
    if (destination.protocol !== 'https:' ||
        !(destination.hostname === 'stripe.com' || destination.hostname.endsWith('.stripe.com'))) {
      return respond({ error: 'Destinazione Stripe non verificabile' }, 502);
    }

    return respond({ onboarding_url: data.url, account_id: TEST_ACCOUNT });
  } catch {
    // Non registrare mai chiavi, token, URL di onboarding o dati personali.
    return respond({ error: 'Attivazione Stripe momentaneamente non disponibile' }, 503);
  }
});
