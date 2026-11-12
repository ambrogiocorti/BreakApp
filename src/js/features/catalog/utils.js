export function parseEuroToCents(value) {
  const text = String(value ?? '').trim();
  if (!/^(?:0|[1-9][0-9]{0,5})(?:[.,][0-9]{1,2})?$/.test(text)) {
    throw new Error('Inserisci un prezzo valido in euro, per esempio 2,50.');
  }
  const [euros, decimals = ''] = text.replace(',', '.').split('.');
  const cents = Number(euros) * 100 + Number(decimals.padEnd(2, '0'));
  if (!Number.isSafeInteger(cents) || cents > 10000000) {
    throw new Error('Prezzo fuori dal limite consentito.');
  }
  return cents;
}

export function formatEuro(cents) {
  if (!Number.isSafeInteger(cents) || cents < 0) {
    throw new Error('Il prezzo in centesimi deve essere un intero non negativo.');
  }
  return new Intl.NumberFormat('it-IT', { style: 'currency', currency: 'EUR' }).format(cents / 100);
}

export function getAdminSchools(access) {
  const schools = new Map();
  for (const membership of access?.memberships || []) {
    const admin = (membership.role_assignments || []).some((role) => role.role_code === 'school_admin');
    if (membership.membership_status !== 'active' || !admin) continue;
    schools.set(membership.school_id, {
      id: membership.school_id,
      name: membership.schools?.name || 'Scuola senza nome'
    });
  }
  return [...schools.values()];
}
