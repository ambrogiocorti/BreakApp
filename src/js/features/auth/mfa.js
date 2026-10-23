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
      if (assurance.data.currentLevel === 'aal2') {
        state('Autenticazione a due fattori verificata. Puoi gestire il catalogo.');
        onAccessChange(true);
        return;
      }
      if (totp) {
        factorId = totp.id;
        codeForm.hidden = false;
        state('Per entrare nell’area Admin inserisci il codice dell’app Authenticator.');
      } else {
        enrollButton.hidden = false;
        state('L’accesso Admin richiede la verifica 2FA. Attivala con un’app Authenticator.');
      }
    } catch (error) {
      if (token !== epoch) return;
      state(error?.message || 'Verifica 2FA non riuscita.', true);
    }
  }

  enrollButton.addEventListener('click', async () => {
    const token = epoch;
    enrollButton.disabled = true;
    state('Generazione del codice QR protetto…');
    try {
      const { data, error } = await client.auth.mfa.enroll({
        factorType: 'totp',
        friendlyName: 'BreakApp Admin'
      });
      if (error) throw error;
      if (token !== epoch) return;
      if (!data?.totp?.qr_code?.startsWith('data:image/')) {
        throw new Error('Impossibile ottenere il QR dalla piattaforma Auth.');
      }
      factorId = data.id;
      qrImage.src = data.totp.qr_code;
      qrPanel.hidden = false;
      codeForm.hidden = false;
      enrollButton.hidden = true;
      state('Scansiona il QR con Google/Microsoft Authenticator, poi inserisci il codice di 6 cifre.');
    } catch (error) {
      if (token !== epoch) return;
      state(error?.message || 'Attivazione non riuscita.', true);
      enrollButton.hidden = false;
    } finally {
      enrollButton.disabled = false;
    }
  });

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
