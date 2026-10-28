import { createClient } from '@supabase/supabase-js';
import { loadSchoolAccess, roleLabel } from './access.js';
import { authRedirectUrl } from './redirect.js';
import { revokeDevicePush } from '../notifications/notifications.js';
import { getAdminSchools } from '../catalog/utils.js';
import { initializeAdminCatalog } from '../catalog/catalog.js';
import { initializeAdminMfa } from './mfa.js';
import { initializeAdminOrderSetup } from '../orders/admin-setup.js';
import {oauthRequest,readOAuthProviders,oauthReturnError,registerWithPassword} from './sign-in.js';

function setFeedback(element, message, isError = false) {
  element.textContent = message;
  element.dataset.type = isError ? 'error' : 'information';
}

export function initializeAuth(config,clientFactory=createClient) {
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
  const menuSection = document.querySelector('#menu');
  const mobileNav = document.querySelector('#app-mobile-nav');
  const desktopNav = document.querySelector('#app-desktop-nav');
  const headerMenu = document.querySelector('#header-menu-link');
  const headerProfile = document.querySelector('#header-profile-link');
  document.body.dataset.authenticated = 'false';


  if (!config.configured) {
    environment.textContent = `Ambiente di sviluppo non collegato: ${config.reason}`;
    environment.dataset.type = 'warning';
    controls.forEach((button) => { button.disabled = true; });
    form.querySelectorAll('input').forEach((input) => { input.disabled = true; });
    setFeedback(feedback, 'Le operazioni di accesso saranno disponibili dopo la configurazione di Supabase.');
    return null;
  }

  environment.textContent = '';
  environment.hidden = true;
  const client = clientFactory(config.url, config.publishableKey,{auth:{flowType:'pkce',detectSessionInUrl:true,persistSession:true,autoRefreshToken:true}});
  let oauthProviders=null,busy=false,providerCheckFailed=false;
  const socialNote=document.getElementById('social-auth-status');
  function refreshSocialControls(){
    google.disabled=busy||oauthProviders?.google!==true;
    microsoft.disabled=busy||oauthProviders?.azure!==true;
    if(socialNote){
      const unavailable=[oauthProviders?.google===false?'Google':null,oauthProviders?.azure===false?'Microsoft':null].filter(Boolean);
      socialNote.hidden=Boolean(oauthProviders)&&!unavailable.length;
      socialNote.textContent=unavailable.length?unavailable.join(' e ')+(unavailable.length===1?' non è disponibile al momento.':' non sono disponibili al momento.')+' Puoi usare email e password.':providerCheckFailed?'Non è possibile verificare gli accessi esterni. Puoi usare email e password.':oauthProviders?'':'Verifica dei metodi di accesso…';
    }
  }
  refreshSocialControls();
  void readOAuthProviders(config).then(providers=>{oauthProviders=providers;refreshSocialControls();}).catch(()=>{providerCheckFailed=true;refreshSocialControls();});
  const callbackError=oauthReturnError(window.location);
  if(callbackError){
    setFeedback(feedback,callbackError,true);
    const clean=new URL(window.location.href);for(const key of ['error','error_code','error_description'])clean.searchParams.delete(key);
    if(new URLSearchParams(clean.hash.slice(1)).has('error'))clean.hash='accesso';
    window.history.replaceState(null,'',clean.pathname+clean.search+clean.hash);
  }

  let activeUser = null;
  let accessRequestId = 0;
  let accessCache = null;
  const catalog = initializeAdminCatalog(client);
  const operations = initializeAdminOrderSetup(client);
  const mfa = initializeAdminMfa(client, (verified) => {
    if (verified && accessCache && activeUser) {
      window.dispatchEvent(new Event('breakapp:mfa-verified'));
      catalog.show(accessCache);
      void operations.show(accessCache);
    } else {
      catalog.hide();
      operations.hide();
    }
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
      window.dispatchEvent(new Event('breakapp:access-updated'));
      const platform=await client.rpc('has_current_platform_admin_role');
      if(requestId!==accessRequestId)return;
      if(getAdminSchools(access).length || (!platform.error&&platform.data===true))
        void mfa.show();
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
    menuSection.hidden = !present;
    mobileNav.hidden = !present;
    desktopNav.hidden = !present;
    headerMenu.hidden = !present;
    headerProfile.hidden = !present;
    document.body.dataset.authenticated = String(present);
    emailLabel.textContent = present ? (user.app_metadata?.guest?(user.user_metadata?.display_name||'Ospite'):(user.email || 'account senza email')) : '';

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
    busy=value;
    controls.forEach((button) => { button.disabled = value; });
    refreshSocialControls();
    logout.disabled = value;
    form.setAttribute('aria-busy',String(value));
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
      () => registerWithPassword(client,credentials,authRedirectUrl(window.location.origin, import.meta.env.BASE_URL)),
      'Richiesta ricevuta. Se necessario, verifica l’indirizzo email per attivare l’account.'
    );
    if (data?.session?.user){showUser(data.session.user);setFeedback(feedback,'Account pronto. Accesso completato.');}
  });
  async function oauth(provider) {
    if(oauthProviders?.[provider]!==true){setFeedback(feedback,'Questo metodo di accesso non è disponibile al momento. Usa email e password.',true);return;}
    await runOperation(
      () => client.auth.signInWithOAuth(oauthRequest(provider,authRedirectUrl(window.location.origin, import.meta.env.BASE_URL))),
      'Reindirizzamento al provider in corso…'
    );
  }
  google.addEventListener('click', () => oauth('google'));
  microsoft.addEventListener('click', () => oauth('azure'));
  logout.addEventListener('click', async () => {
    let pushWarning=false;
    try { await revokeDevicePush(client); }
    catch { pushWarning=true; }
    const data = await runOperation(() => client.auth.signOut(), 'Disconnessione completata.');
    if (data !== null) {
      showUser(null);
      if(pushWarning)setFeedback(feedback,
        'Disconnessione completata, ma la revoca delle push non è stata confermata. Verifica le notifiche del browser su questo dispositivo condiviso.',true);
    }
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
  return client;
}
