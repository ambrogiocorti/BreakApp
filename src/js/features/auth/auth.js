import { createClient } from '@supabase/supabase-js';
import { loadSchoolAccess, roleLabel } from './access.js';
import { getAdminSchools } from '../catalog/utils.js';
import { initializeAdminCatalog } from '../catalog/catalog.js';
import { initializeAdminMfa } from './mfa.js';

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
  const accessSummary = document.querySelector('#school-access-status');
  const schoolList = document.querySelector('#school-access-list');
  const refreshAccessButton = document.querySelector('#refresh-access-button');

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

  let activeUser = null;
  let accessRequestId = 0;
  let accessCache = null;
  const catalog = initializeAdminCatalog(client);
  const mfa = initializeAdminMfa(client, (verified) => {
    if (verified && accessCache && activeUser) catalog.show(accessCache);
    else catalog.hide();
  });

  function renderSchoolAccess({ memberships, bars }) {
    schoolList.replaceChildren();
    if (memberships.length === 0) {
      accessSummary.textContent = 'Il tuo account non risulta ancora associato a una scuola attiva. Verifica l’assegnazione in Supabase.';
      return;
    }

    accessSummary.textContent = `Scuole associate al tuo account: ${memberships.length}.`;
    for (const membership of memberships) {
      const article = document.createElement('article');
      article.className = 'school-access-card';

      const title = document.createElement('h4');
      title.textContent = membership.schools?.name || 'Scuola non disponibile';
      article.append(title);

      const roles = document.createElement('div');
      roles.className = 'school-role-list';
      const assignedRoles = (membership.role_assignments || []).map((role) => role.role_code);
      for (const role of assignedRoles) {
        const chip = document.createElement('span');
        chip.className = 'school-role-chip';
        chip.textContent = roleLabel(role);
        roles.append(chip);
      }
      if (assignedRoles.length === 0) {
        const message = document.createElement('p');
        message.className = 'school-access-empty';
        message.textContent = 'Nessun ruolo attivo assegnato.';
        article.append(message);
      } else {
        article.append(roles);
      }

      const schoolBars = bars.filter((bar) => bar.school_id === membership.school_id);
      const barLabel = document.createElement('p');
      barLabel.className = 'school-bars-label';
      barLabel.textContent = schoolBars.length
        ? `Bar: ${schoolBars.map((bar) => bar.name).join(', ')}`
        : 'Nessun bar attivo visibile.';
      article.append(barLabel);

      if (assignedRoles.includes('school_admin')) {
        const note = document.createElement('p');
        note.className = 'school-admin-note';
        note.textContent = 'Ruolo Admin riconosciuto. Il catalogo richiede la verifica 2FA obbligatoria e le policy RLS.';
        article.append(note);
      }

      schoolList.append(article);
    }
  }

  async function refreshSchoolAccess(user) {
    const requestId = ++accessRequestId;
    refreshAccessButton.disabled = true;
    accessSummary.textContent = 'Verifica autorizzazioni dal database in corso…';
    schoolList.replaceChildren();
    accessCache = null;
    mfa.hide();
    try {
      const access = await loadSchoolAccess(client, user.id);
      if (requestId !== accessRequestId) return;
      accessCache = access;
      renderSchoolAccess(access);
      if (getAdminSchools(access).length) void mfa.show();
    } catch (error) {
      if (requestId !== accessRequestId) return;
      accessSummary.textContent = error?.message || 'Impossibile leggere le autorizzazioni. Riprova.';
      accessSummary.dataset.type = 'error';
    } finally {
      if (requestId === accessRequestId) refreshAccessButton.disabled = false;
    }
  }

  function showUser(user) {
    const present = Boolean(user);
    signedIn.hidden = !present;
    signedOut.hidden = present;
    emailLabel.textContent = present ? (user.email || 'account senza email') : '';

    if (!present) {
      activeUser = null;
      accessRequestId += 1;
      accessCache = null;
      mfa.hide();
      schoolList.replaceChildren();
      accessSummary.textContent = '';
      return;
    }
    if (activeUser?.id !== user.id) {
      activeUser = user;
      accessSummary.dataset.type = 'information';
      // Non eseguire chiamate Supabase in modo sincrono nel callback Auth.
      queueMicrotask(() => {
        if (activeUser?.id === user.id) refreshSchoolAccess(user);
      });
    }
  }

  refreshAccessButton.addEventListener('click', () => {
    if (activeUser) {
      accessSummary.dataset.type = 'information';
      void refreshSchoolAccess(activeUser);
    }
  });
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
