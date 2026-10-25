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
  const backupButton = document.querySelector('#mfa-backup-button');
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
    backupButton.hidden = true;
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
        state('Autenticazione a due fattori verificata. Puoi gestire il catalogo. Per non perdere l’accesso, registra anche un Authenticator di riserva.');
        backupButton.hidden = false;
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

  async function enrollNewFactor(isBackup) {
    const token = epoch;
    const source = isBackup ? backupButton : enrollButton;
    source.disabled = true;
    state('Generazione del nuovo QR protetto…');
    try {
      // Un secondo fattore di riserva è consentito soltanto dopo aver raggiunto AAL2.
      if (isBackup) {
        const assurance = await client.auth.mfa.getAuthenticatorAssuranceLevel();
        if (assurance.error) throw assurance.error;
        if (assurance.data.currentLevel !== 'aal2') {
          throw new Error('Verifica prima la 2FA corrente per aggiungere un dispositivo di riserva.');
        }
      } else {
        // Evita che un utente in AAL1 aggiri un vecchio fattore TOTP verificato.
        const factors = await client.auth.mfa.listFactors();
        if (factors.error) throw factors.error;
        if (factors.data.totp?.some((item) => item.status === 'verified')) {
          throw new Error('Il fattore esistente deve essere rimosso tramite recupero amministrativo autorizzato prima di generare un nuovo QR.');
        }
      }
      const { data, error } = await client.auth.mfa.enroll({
        factorType: 'totp',
        friendlyName: isBackup ? `BreakApp riserva ${Date.now()}` : 'BreakApp Admin'
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
      backupButton.hidden = true;
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
  enrollButton.addEventListener('click', () => { void enrollNewFactor(false); });
  backupButton.addEventListener('click', () => { void enrollNewFactor(true); });
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
