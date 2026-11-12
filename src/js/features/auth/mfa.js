/**
 * 2FA TOTP reale Supabase Auth. La UI non attribuisce ruoli:
 * il database applica sempre la condizione JWT aal2 per ogni scrittura admin.
 */
export function initializeAdminMfa(client, onAccessChange) {
  const panel = document.querySelector('#admin-mfa');
  const status = document.querySelector('#mfa-status');
  const enrollButton = document.querySelector('#mfa-enroll-button');
  const qrPanel = document.querySelector('#mfa-qr-panel');
  const qrImage = document.querySelector('#mfa-qr');
  const codeForm = document.querySelector('#mfa-code-form');
  const codeInput = document.querySelector('#mfa-code');
  const codeButton = document.querySelector('#mfa-code-button');
  const lostPanel = document.querySelector('#mfa-lost-panel');
  const refreshButton = document.querySelector('#mfa-refresh-button');
  let factorId = null;
  let epoch = 0;

  function state(message, error = false) {
    status.textContent = message;
    status.dataset.type = error ? 'error' : 'information';
  }
  function clearSensitive() {
    qrImage.removeAttribute('src');
    qrPanel.hidden = true;
    codeInput.value = '';
    lostPanel.hidden = true;
  }
  function hide() {
    epoch += 1;
    factorId = null;
    clearSensitive();
    panel.hidden = true;
    onAccessChange(false);
  }

  async function show() {
    const token = ++epoch;
    panel.hidden = false;
    clearSensitive();
    factorId = null;
    enrollButton.hidden = true;
    codeForm.hidden = true;
    onAccessChange(false);
    state('Verifica dello stato della sicurezza in corso…');
    try {
      const [factors, assurance] = await Promise.all([
        client.auth.mfa.listFactors(),
        client.auth.mfa.getAuthenticatorAssuranceLevel()
      ]);
      if (token !== epoch) return;
      if (factors.error) throw factors.error;
      if (assurance.error) throw assurance.error;
      const totp = (factors.data.totp || []).find((factor) => factor.status === 'verified');
      if (assurance.data.currentLevel === 'aal2' && totp) {
        state('Verifica in due passaggi completata. Le funzioni amministrative sono abilitate.');
        onAccessChange(true);
        return;
      }
      if (totp) {
        factorId = totp.id;
        codeForm.hidden = false;
        lostPanel.hidden = false;
        state('Inserisci il codice dell’app Authenticator già associata. Il QR iniziale non può essere mostrato nuovamente.');
      } else {
        enrollButton.hidden = false;
        state('L’accesso Admin richiede la verifica 2FA. Attivala con un’app Authenticator.');
      }
    } catch (error) {
      if (token !== epoch) return;
      state(error?.message || 'Verifica 2FA non riuscita.', true);
    }
  }

  async function enrollNewFactor() {
    if(enrollButton.disabled)return;
    const token = epoch;
    const source = enrollButton;
    source.disabled = true;
    state('Generazione del nuovo QR protetto…');
    try {
      // Never enroll a second verified Authenticator, including from an AAL2 session.
      const factors = await client.auth.mfa.listFactors();
      if(token!==epoch)return;
      if (factors.error) throw factors.error;
      if (factors.data.totp?.some((item) => item.status === 'verified')) {
        source.hidden=true;
        state('Il fattore esistente deve essere rimosso tramite recupero amministrativo autorizzato prima di generare un nuovo QR.',true);
        return;
      }
      // A QR that was never verified cannot be retrieved again. Restart only an
      // unfinished enrollment, never remove a verified factor from this screen.
      for(const pending of factors.data.totp||[]){
        const removed=await client.auth.mfa.unenroll({factorId:pending.id});
        if(token!==epoch)return;if(removed.error)throw removed.error;
      }
      const { data, error } = await client.auth.mfa.enroll({
        factorType: 'totp',
        friendlyName: 'BreakApp Admin'
      });
      if (error) throw error;
      if (token !== epoch) return;
      // Il QR è generato da Supabase e non va memorizzato in localStorage o nei log.
      if (!data?.totp?.qr_code?.startsWith('data:image/')) {
        throw new Error('Impossibile ottenere il QR dalla piattaforma Auth.');
      }
      factorId = data.id;
      qrImage.src = data.totp.qr_code;
      qrPanel.hidden = false;
      codeForm.hidden = false;
      enrollButton.hidden = true;
      lostPanel.hidden = true;
      state('Nuovo QR generato. Scansionalo in Authenticator e inserisci il codice a 6 cifre per attivarlo.');
    } catch (error) {
      if (token !== epoch) return;
      state(error?.message || 'Impossibile generare il nuovo QR. Riprova.', true);
      source.hidden = false;
    } finally {
      source.disabled = false;
    }
  }
  enrollButton.addEventListener('click', () => { void enrollNewFactor(); });
  refreshButton.addEventListener('click', () => { void show(); });

  codeForm.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!factorId || !/^\d{6}$/.test(codeInput.value.trim())) {
      state('Inserisci le sei cifre generate dall’app.', true);
      return;
    }
    const token = epoch;
    codeButton.disabled = true;
    try {
      const { error } = await client.auth.mfa.challengeAndVerify({
        factorId,
        code: codeInput.value.trim()
      });
      if (error) throw error;
      if (token !== epoch) return;
      // La libreria aggiorna la sessione: rileggiamo l'AAL prima di abilitare la UI.
      await show();
    } catch (error) {
      if (token !== epoch) return;
      state(error?.message || 'Codice non valido. Riprova.', true);
      codeInput.select();
    } finally {
      codeButton.disabled = false;
    }
  });

  return { show, hide };
}
