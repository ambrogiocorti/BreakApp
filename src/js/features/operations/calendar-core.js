export const WEEKDAY_LABELS = Object.freeze(['Domenica','Lunedì','Martedì','Mercoledì','Giovedì','Venerdì','Sabato']);

export function parseWeeklyPeriods(text) {
  const lines = String(text ?? '').split(/\r?\n/).map(v => v.trim()).filter(Boolean);
  if (lines.length > 8) throw new Error('Massimo otto intervalli per giorno.');
  const periods = lines.map(line => {
    const match = /^([0-2]\d:[0-5]\d)\s*-\s*([0-2]\d:[0-5]\d)$/.exec(line);
    if (!match || match[1] >= match[2] || match[1].slice(0,2) > '23'
      || match[2].slice(0,2) > '23') {
      throw new Error('Scrivi un intervallo valido per riga, ad esempio 08:00-12:00.');
    }
    return { starts_at: match[1], ends_at: match[2] };
  }).sort((a,b)=>a.starts_at.localeCompare(b.starts_at));
  for (let i=1; i<periods.length; i++) {
    if(periods[i].starts_at < periods[i-1].ends_at)
      throw new Error('Gli intervalli di apertura non possono sovrapporsi.');
  }
  return periods;
}

export function isWindowBlocked(slot, closures = []) {
  if (!slot?.service_date || !slot?.starts_at || !slot?.ends_at) return true;
  return closures.some(c =>
    c.reopened_at == null && c.service_date===slot.service_date
    && c.starts_at < slot.ends_at && c.ends_at > slot.starts_at
  );
}

export function formatWeeklyPeriods(periods) {
  return periods.map(p=>p.starts_at.slice(0,5)+'–'+p.ends_at.slice(0,5)).join(', ') || 'Chiuso';
}
