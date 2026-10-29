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
  'access-control-allow-headers': 'authorization, apikey, content-type',
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

    const response = await fetch('https://api.stripe.com/v2/core/account_links', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + stripeKey,
        'Content-Type': 'application/json',
        'Stripe-Version': '2026-09-30.preview'
      },
      body: JSON.stringify({
        account: TEST_ACCOUNT,
        use_case: {
          type: 'account_onboarding',
          account_onboarding: {
            collection_options: { fields: 'eventually_due' },
            return_url: RETURN_URL,
            refresh_url: RETURN_URL
          }
        }
      })
    });

    if (!response.ok) {
      // I messaggi Stripe possono contenere dati dell'account: non inoltrarli.
      return respond({ error: 'Stripe non ha generato il link (' + response.status + '). Controlla la chiave e i permessi Account Links.' }, 502);
    }

    const data = await response.json() as { url?: unknown; expires_at?: unknown };
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
