import '../css/base.css';
import { readSupabaseConfig } from './core/config.js';
import { initializeTheme } from './core/theme.js';
import { initializeAuth } from './features/auth/auth.js';

initializeTheme();
initializeAuth(readSupabaseConfig(import.meta.env));

// Cache statica soltanto: nessuna vendita, consegna o incasso offline in Fase 1.
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(() => { /* l'app online resta utilizzabile */ });
  });
}
