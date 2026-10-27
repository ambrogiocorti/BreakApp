// Returns the exact published PWA URL for Supabase Auth callbacks.
// GitHub Pages project sites live under /BreakApp/, custom domains under /.
// Never allow a configured base path to escape to another origin.
export function authRedirectUrl(origin, basePath) {
  const site = new URL(origin);
  const local = ['localhost', '127.0.0.1'].includes(site.hostname);
  if (site.protocol !== 'https:' && !(local && site.protocol === 'http:')) {
    throw new Error('Origine Auth non sicura.');
  }
  if (!/^\/(?:[A-Za-z0-9._~-]+\/)*$/.test(basePath)) {
    throw new Error('Percorso pubblico della PWA non valido.');
  }
  if (basePath.split('/').some(part => part === '.' || part === '..')) {
    throw new Error('Percorso pubblico della PWA non valido.');
  }
  return new URL(basePath, site.origin).href;
}
