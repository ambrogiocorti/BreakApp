import { parseEuroToCents, formatEuro, getAdminSchools } from './utils.js';

function element(tag, className, value) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (value !== undefined) node.textContent = value;
  return node;
}

/**
 * CRUD browser -> Supabase con RLS per tenant, ruolo e AAL2.
 * I controlli JS sono soltanto UX; nessuna autorizzazione dipende dal browser.
 */
export function initializeAdminCatalog(client) {
  const panel = document.querySelector('#admin-catalog');
  const schoolSelect = document.querySelector('#catalog-school');
  const barSelect = document.querySelector('#catalog-bar');
  const status = document.querySelector('#catalog-status');
  const refreshButton = document.querySelector('#catalog-refresh');
  const categoriesList = document.querySelector('#catalog-categories-list');
  const productsList = document.querySelector('#catalog-products-list');
  const categoryForm = document.querySelector('#catalog-category-form');
  const categoryName = document.querySelector('#catalog-category-name');
  const categorySubmit = document.querySelector('#catalog-category-submit');
  const categoryCancel = document.querySelector('#catalog-category-cancel');
  const productForm = document.querySelector('#catalog-product-form');
  const productCategory = document.querySelector('#catalog-product-category');
  const productName = document.querySelector('#catalog-product-name');
  const productDescription = document.querySelector('#catalog-product-description');
  const productPrice = document.querySelector('#catalog-product-price');
  const productSubmit = document.querySelector('#catalog-product-submit');
  const productCancel = document.querySelector('#catalog-product-cancel');
  let access = null;
  let categories = [];
  let products = [];
  let generation = 0;
  let isBusy = false;

  function notify(message, isError = false) {
    status.textContent = message;
    status.dataset.type = isError ? 'error' : 'information';
  }
  function selected() {
    const school_id = schoolSelect.value;
    const bar_id = barSelect.value;
    const allowed = getAdminSchools(access).some((item) => item.id === school_id)
      && (access?.bars || []).some((bar) => bar.school_id === school_id && bar.id === bar_id);
    if (!allowed) throw new Error('Seleziona una scuola e un bar a cui sei autorizzato.');
    return { school_id, bar_id };
  }
  function resetCategoryForm() {
    categoryForm.reset();
    categoryForm.dataset.editId = '';
    categorySubmit.textContent = 'Aggiungi categoria';
    categoryCancel.hidden = true;
  }
  function resetProductForm() {
    productForm.reset();
    productForm.dataset.editId = '';
    productSubmit.textContent = 'Aggiungi prodotto';
    productCancel.hidden = true;
  }
  function resetForms() {
    resetCategoryForm();
    resetProductForm();
  }
  function hide() {
    generation++;
    panel.hidden = true;
    access = null;
    categories = [];
    products = [];
    resetForms();
    categoriesList.replaceChildren();
    productsList.replaceChildren();
  }
  function fillBars() {
    const previous = barSelect.value;
    barSelect.replaceChildren();
    for (const bar of (access?.bars || []).filter((item) => item.school_id === schoolSelect.value)) {
      const option = new Option(bar.name, bar.id);
      barSelect.add(option);
    }
    if ([...barSelect.options].some((option) => option.value === previous)) barSelect.value = previous;
    resetForms();
  }
  function show(nextAccess) {
    access = nextAccess;
    const schools = getAdminSchools(access);
    if (!schools.length) { hide(); return; }
    panel.hidden = false;
    const previous = schoolSelect.value;
    schoolSelect.replaceChildren();
    for (const school of schools) schoolSelect.add(new Option(school.name, school.id));
    if (schools.some((school) => school.id === previous)) schoolSelect.value = previous;
    fillBars();
    void refresh();
  }
  function render() {
    categoriesList.replaceChildren();
    productsList.replaceChildren();
    productCategory.replaceChildren();
    for (const category of categories) {
      productCategory.add(new Option(
        category.is_active ? category.name : `${category.name} (nascosta)`,
        category.id
      ));
      const row = element('div', 'catalog-item');
      const description = element('div', 'catalog-item-description');
      description.append(element('strong', '', category.name),
        element('span', 'catalog-item-meta', category.is_active ? 'Visibile' : 'Nascosta'));
      const buttons = element('div', 'catalog-item-actions');
      const edit = element('button', 'button button-outline button-small', 'Modifica');
      edit.type = 'button';
      edit.addEventListener('click', () => {
        categoryForm.dataset.editId = category.id;
        categoryName.value = category.name;
        categorySubmit.textContent = 'Salva categoria';
        categoryCancel.hidden = false;
        categoryName.focus();
      });
      const toggle = element('button', 'button button-secondary button-small',
        category.is_active ? 'Nascondi' : 'Riattiva');
      toggle.type = 'button';
      toggle.addEventListener('click', () => { void toggleActive('categories', category); });
      buttons.append(edit, toggle);
      row.append(description, buttons);
      categoriesList.append(row);
    }
    for (const product of products) {
      const row = element('div', 'catalog-item');
      const description = element('div', 'catalog-item-description');
      const category = categories.find((item) => item.id === product.category_id);
      const heading = element('strong', '', `${product.name} · ${formatEuro(product.price_cents)}`);
      description.append(heading, element('span', 'catalog-item-meta',
        `${category?.name || 'Categoria non disponibile'} · ${product.is_active ? 'Visibile' : 'Nascosto'}`));
      if (product.description) description.append(element('span', 'catalog-item-meta', product.description));
      const buttons = element('div', 'catalog-item-actions');
      const edit = element('button', 'button button-outline button-small', 'Modifica');
      edit.type = 'button';
      edit.addEventListener('click', () => {
        productForm.dataset.editId = product.id;
        productCategory.value = product.category_id;
        productName.value = product.name;
        productDescription.value = product.description;
        productPrice.value = (product.price_cents / 100).toFixed(2).replace('.', ',');
        productSubmit.textContent = 'Salva prodotto';
        productCancel.hidden = false;
        productName.focus();
      });
      const toggle = element('button', 'button button-secondary button-small',
        product.is_active ? 'Nascondi' : 'Riattiva');
      toggle.type = 'button';
      toggle.addEventListener('click', () => { void toggleActive('products', product); });
      buttons.append(edit, toggle);
      row.append(description, buttons);
      productsList.append(row);
    }
    if (!categories.length) categoriesList.append(element('p', 'catalog-empty', 'Nessuna categoria: aggiungi la prima.'));
    if (!products.length) productsList.append(element('p', 'catalog-empty', 'Nessun prodotto: crea una categoria, poi aggiungi il primo.'));
    productSubmit.disabled = !productCategory.options.length;
  }
  async function refresh() {
    if (panel.hidden || !access) return;
    const token = ++generation;
    resetForms();
    categoriesList.replaceChildren();
    productsList.replaceChildren();
    if (!barSelect.value) {
      notify('Non ci sono bar associati alla scuola selezionata.');
      productSubmit.disabled = true;
      return;
    }
    notify('Caricamento categorie e prodotti dal database…');
    const scope = selected();
    try {
      const [categoryResult, productResult] = await Promise.all([
        client.from('categories').select('id,school_id,bar_id,name,sort_order,is_active')
          .eq('school_id', scope.school_id).eq('bar_id', scope.bar_id)
          .order('sort_order').order('name'),
        client.from('products').select('id,school_id,bar_id,category_id,name,description,price_cents,is_active')
          .eq('school_id', scope.school_id).eq('bar_id', scope.bar_id).order('name')
      ]);
      if (token !== generation || panel.hidden) return;
      if (categoryResult.error) throw categoryResult.error;
      if (productResult.error) throw productResult.error;
      categories = categoryResult.data || [];
      products = productResult.data || [];
      render();
      notify(`Catalogo sincronizzato: ${categories.length} categorie · ${products.length} prodotti.`);
    } catch (error) {
      if (token !== generation || panel.hidden) return;
      if (error?.code === 'PGRST205' || error?.code === '42P01') {
        notify('Le tabelle non sono ancora presenti: esegui lo script SQL 03 nel nuovo Supabase.', true);
      } else {
        notify(error?.message || 'Impossibile leggere il catalogo.', true);
      }
    }
  }
  async function save(table, payload, editId) {
    if (isBusy) return;
    isBusy = true;
    categorySubmit.disabled = true;
    productSubmit.disabled = true;
    const token = generation;
    try {
      const scope = selected();
      const query = editId
        ? client.from(table).update(payload).eq('id', editId)
          .eq('school_id', scope.school_id).eq('bar_id', scope.bar_id)
        : client.from(table).insert({ ...scope, ...payload });
      const { data, error } = await query.select('id').single();
      if (error) throw error;
      if (!data?.id) throw new Error('Nessun elemento aggiornato: controlla ruolo, 2FA e policy RLS.');
      if (token !== generation) return;
      await refresh();
      notify(editId ? 'Modifiche salvate su Supabase.' : 'Elemento creato su Supabase.');
    } catch (error) {
      if (token === generation) notify(error?.message || 'Salvataggio non riuscito.', true);
    } finally {
      isBusy = false;
      categorySubmit.disabled = false;
      productSubmit.disabled = !productCategory.options.length;
    }
  }
  async function toggleActive(table, record) {
    await save(table, { is_active: !record.is_active }, record.id);
  }

  categoryForm.addEventListener('submit', (event) => {
    event.preventDefault();
    if (!categoryForm.reportValidity()) return;
    void save('categories', { name: categoryName.value.trim() }, categoryForm.dataset.editId);
  });
  productForm.addEventListener('submit', (event) => {
    event.preventDefault();
    if (!productForm.reportValidity()) return;
    try {
      const payload = {
        category_id: productCategory.value,
        name: productName.value.trim(),
        description: productDescription.value.trim(),
        price_cents: parseEuroToCents(productPrice.value)
      };
      if (!payload.category_id) throw new Error('Devi scegliere una categoria.');
      void save('products', payload, productForm.dataset.editId);
    } catch (error) { notify(error.message, true); }
  });
  categoryCancel.addEventListener('click', resetCategoryForm);
  productCancel.addEventListener('click', resetProductForm);
  schoolSelect.addEventListener('change', () => { fillBars(); void refresh(); });
  barSelect.addEventListener('change', () => { void refresh(); });
  refreshButton.addEventListener('click', () => { void refresh(); });

  return { show, hide };
}
