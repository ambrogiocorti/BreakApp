/**
 * Lettura in sola modalità READ delle appartenenze autorizzate dalle policy RLS.
 * Nessun ruolo viene mai assegnato sulla base di dati locali, email o user_metadata.
 */
const roleLabels = Object.freeze({
  school_admin: 'Admin scuola',
  warehouse_manager: 'Magazziniere',
  bartender: 'Barista',
  customer: 'Cliente'
});

export function roleLabel(roleCode) {
  return roleLabels[roleCode] || 'Ruolo non riconosciuto';
}

export async function loadSchoolAccess(client, userId) {
  if (!userId) throw new Error('Utente non autenticato.');

  const { data: memberships, error: membershipError } = await client
    .from('school_memberships')
    .select('id, school_id, membership_status, schools(id, name, slug), role_assignments(role_code)')
    .eq('user_id', userId)
    .eq('membership_status', 'active');

  if (membershipError) throw membershipError;
  const activeMemberships = memberships || [];
  const schoolIds = [...new Set(activeMemberships.map((item) => item.school_id))];
  if (schoolIds.length === 0) return { memberships: [], bars: [] };

  const { data: bars, error: barsError } = await client
    .from('bars')
    .select('id, school_id, name')
    .in('school_id', schoolIds)
    .order('name', { ascending: true });

  if (barsError) throw barsError;
  return { memberships: activeMemberships, bars: bars || [] };
}
