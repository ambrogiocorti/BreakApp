// Explains the location check in plain words. It never decides anything: the
// device reading goes to the server, which checks accuracy (100 m) and the
// school's radius. Distance and accuracy are different problems and are worded
// differently on purpose.
const STATES = Object.freeze({
  idle: null,
  pending: { title: 'Verifica della posizione…', tips: [] },
  improving: { title: 'Stiamo migliorando la precisione…', tips: ['Resta fermo qualche secondo, vicino a una finestra o all’aperto.'] },
  permission: {
    state: 'denied', title: 'Posizione non consentita',
    tips: ['Consenti la posizione per questo sito nelle impostazioni del browser.', 'Sul telefono controlla anche che la localizzazione sia attiva.', 'Poi premi di nuovo il pulsante.']
  },
  accuracy: {
    state: 'weak', title: 'Posizione troppo approssimativa',
    tips: ['Attiva la «posizione precisa» per il browser.', 'Spostati vicino a una finestra o all’aperto e riprova.']
  },
  unavailable: { state: 'unavailable', title: 'Posizione non disponibile', tips: ['Attiva i servizi di localizzazione del dispositivo e riprova.'] },
  timeout: { state: 'timeout', title: 'La posizione non è arrivata in tempo', tips: ['Controlla che la localizzazione sia attiva e riprova vicino a una finestra.'] },
  clock: { state: 'error', title: 'Orario del dispositivo non valido', tips: ['Attiva data e ora automatiche, oppure prova con un altro browser.'] },
  stale: { state: 'weak', title: 'Posizione non recente', tips: ['Riattiva la localizzazione e riprova.'] },
  unsupported: { state: 'unavailable', title: 'Posizione non supportata', tips: ['Prova con un browser aggiornato (Chrome, Safari, Firefox o Edge).'] },
  far: { state: 'far', title: 'Sei fuori dall’area della scuola', tips: ['La prenotazione si conferma solo entro il raggio stabilito dalla scuola.', 'Riprova quando sei a scuola.'] },
  server_accuracy: { state: 'weak', title: 'Il server non ha accettato la precisione', tips: ['Serve una misura entro 100 m: attiva la posizione precisa e riprova all’aperto.'] },
  not_configured: { state: 'error', title: 'Posizione della scuola non configurata', tips: ['Avvisa l’Admin della scuola: senza coordinate non si possono confermare prenotazioni.'] },
  ok: { state: 'ok', title: 'Posizione verificata', tips: [] }
});

/** Maps a device or server error to a location state key, or null if unrelated. */
export function locationProblem(error) {
  if (!error) return null;
  if (error.code && STATES[error.code] && typeof error.code === 'string') return error.code;
  const text = String(error.message || error);
  if (/raggio|fuori dall|esterna al/i.test(text)) return 'far';
  if (/precis|accura/i.test(text)) return 'server_accuracy';
  if (/posizione (della )?scuola non configurata/i.test(text)) return 'not_configured';
  if (/posizione non verificabile/i.test(text)) return 'server_accuracy';
  return null;
}

/** Renders the state into a `.location-check` container. */
export function showLocation(container, key, { why = '', detail = '' } = {}) {
  if (!container) return;
  if (!container.dataset.why) container.dataset.why = container.querySelector('.location-why')?.textContent || why;
  const config = STATES[key];
  container.replaceChildren();
  if (!config) {
    container.dataset.state = 'idle';
    if (container.dataset.why) {
      const p = document.createElement('p'); p.className = 'location-why'; p.textContent = container.dataset.why; container.append(p);
    }
    return;
  }
  container.dataset.state = config.state || key;
  const title = document.createElement('strong'); title.textContent = config.title;
  container.append(title);
  if (detail) { const p = document.createElement('p'); p.textContent = detail; container.append(p); }
  if (config.tips.length) {
    const list = document.createElement('ul');
    for (const tip of config.tips) { const li = document.createElement('li'); li.textContent = tip; list.append(li); }
    container.append(list);
  }
}
