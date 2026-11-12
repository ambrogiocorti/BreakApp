/** Configurazione pubblica: non contiene né sostituisce autorizzazioni server. */
export function readSupabaseConfig(env) {
  const urlText = String(env?.VITE_SUPABASE_URL ?? '').trim();
  const key = String(env?.VITE_SUPABASE_PUBLISHABLE_KEY ?? '').trim();
  if (!urlText || !key || urlText.includes('your-project') || key.endsWith('_example')) {
    return { configured: false, reason: 'Configura il progetto Supabase di sviluppo nel file .env.' };
  }
  if (!key.startsWith('sb_publishable_')) {
    return { configured: false, reason: 'Usa soltanto la chiave pubblicabile Supabase (sb_publishable_…).' };
  }
  try {
    const url = new URL(urlText);
    const local = ['localhost', '127.0.0.1'].includes(url.hostname);
    if (url.protocol !== 'https:' && !(local && url.protocol === 'http:')) {
      return { configured: false, reason: 'L’URL Supabase deve utilizzare HTTPS.' };
    }
    if (url.username || url.password || url.search || url.hash) {
      return { configured: false, reason: 'L’URL Supabase contiene parametri non consentiti.' };
    }
    return { configured: true, url: url.origin, publishableKey: key };
  } catch {
    return { configured: false, reason: 'URL Supabase non valido.' };
  }
}
