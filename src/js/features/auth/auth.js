import { createClient } from '@supabase/supabase-js';

function setFeedback(element, message, isError = false) {
  element.textContent = message;
  element.dataset.type = isError ? 'error' : 'information';
}

export function initializeAuth(config) {
  const environment = document.querySelector('#environment-status');
  const feedback = document.querySelector('#auth-feedback');
  const signedIn = document.querySelector('#signed-in-view');
  const signedOut = document.querySelector('#signed-out-view');
  const emailLabel = document.querySelector('#user-email');
  const form = document.querySelector('#auth-form');
  const signup = document.querySelector('#signup-button');
  const login = document.querySelector('#login-button');
  const logout = document.querySelector('#logout-button');
  const google = document.querySelector('#google-button');
  const microsoft = document.querySelector('#microsoft-button');
  const controls = [login, signup, google, microsoft];

  if (!config.configured) {
    environment.textContent = `Ambiente di sviluppo non collegato: ${config.reason}`;
    environment.dataset.type = 'warning';
    controls.forEach((button) => { button.disabled = true; });
    form.querySelectorAll('input').forEach((input) => { input.disabled = true; });
    setFeedback(feedback, 'Le operazioni di accesso saranno disponibili dopo la configurazione di Supabase.');
    return;
  }

  environment.textContent = 'Chiave pubblicabile configurata. Accesso gestito da Supabase Auth.';
  environment.dataset.type = 'success';
  const client = createClient(config.url, config.publishableKey);

  function showUser(user) {
    const present = Boolean(user);
    signedIn.hidden = !present;
    signedOut.hidden = present;
    emailLabel.textContent = present ? (user.email || 'account senza email') : '';
  }
  function setBusy(value) {
    controls.forEach((button) => { button.disabled = value; });
    logout.disabled = value;
  }
  async function runOperation(operation, successMessage) {
    setBusy(true);
    setFeedback(feedback, 'Operazione in corso…');
    try {
      const { data, error } = await operation();
      if (error) throw error;
      setFeedback(feedback, successMessage);
      return data ?? {};
    } catch (error) {
      setFeedback(feedback, error?.message || 'Operazione non riuscita. Riprova.', true);
      return null;
    } finally {
      setBusy(false);
    }
  }
  function getCredentials() {
    if (!form.reportValidity()) return null;
    const email = document.querySelector('#auth-email').value.trim();
    const password = document.querySelector('#auth-password').value;
    if (!email || password.length < 8) {
      setFeedback(feedback, 'Inserisci email e password di almeno 8 caratteri.', true);
      return null;
    }
    return { email, password };
  }

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const credentials = getCredentials();
    if (!credentials) return;
    const data = await runOperation(() => client.auth.signInWithPassword(credentials), 'Accesso completato.');
    if (data?.user) showUser(data.user);
  });
  signup.addEventListener('click', async () => {
    const credentials = getCredentials();
    if (!credentials) return;
    const data = await runOperation(
      () => client.auth.signUp({
        ...credentials,
        options: { emailRedirectTo: window.location.origin + '/' }
      }),
      'Richiesta ricevuta. Se necessario, verifica l’indirizzo email per attivare l’account.'
    );
    if (data?.session?.user) showUser(data.session.user);
  });
  async function oauth(provider) {
    await runOperation(
      () => client.auth.signInWithOAuth({ provider, options: { redirectTo: window.location.origin + '/' } }),
      'Reindirizzamento al provider in corso…'
    );
  }
  google.addEventListener('click', () => oauth('google'));
  microsoft.addEventListener('click', () => oauth('azure'));
  logout.addEventListener('click', async () => {
    const data = await runOperation(() => client.auth.signOut(), 'Disconnessione completata.');
    if (data !== null) showUser(null);
  });

  client.auth.onAuthStateChange((_event, session) => {
    // UI soltanto: non assegnare né inferire ruoli da questa sessione.
    showUser(session?.user ?? null);
  });
  client.auth.getUser().then(({ data, error }) => {
    if (error || !data?.user) showUser(null);
    else showUser(data.user);
  }).catch(() => {
    showUser(null);
    setFeedback(feedback, 'Non è stato possibile verificare la sessione.', true);
  });
}
