/**
 * Filtro lato client per il menu pubblico; la sicurezza dei record visibili
 * rimane nelle policy RLS di Supabase.
 */
export function filterPublicMenu(categories, products, { categoryId = 'all', search = '' } = {}) {
  const visible = new Set(
    (categories || []).filter((category) => category.is_active).map((category) => category.id)
  );
  const query = String(search).trim().toLocaleLowerCase('it-IT');
  return (products || []).filter((product) => {
    if (!product.is_active || !visible.has(product.category_id)) return false;
    if (categoryId !== 'all' && product.category_id !== categoryId) return false;
    return !query || `${product.name || ''} ${product.description || ''}`
      .toLocaleLowerCase('it-IT').includes(query);
  });
}

export function barsForSchool(bars, schoolId) {
  return (bars || []).filter((bar) => bar.is_active && bar.school_id === schoolId);
}
