import { formatEuro } from '../catalog/utils.js';
import { barsForSchool, filterPublicMenu } from './utils.js';

const ALLERGEN_LABELS = Object.freeze({
  gluten:'Glutine', crustaceans:'Crostacei', eggs:'Uova', fish:'Pesce',
  peanuts:'Arachidi', soy:'Soia', milk:'Latte', nuts:'Frutta a guscio',
  celery:'Sedano', mustard:'Senape', sesame:'Sesamo', sulphites:'Solfiti',
  lupin:'Lupini', molluscs:'Molluschi'
});
function make(tag, className, value) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (value !== undefined) element.textContent = value;
  return element;
}

/**
 * Catalogo pubblico online. Gli ordini sono intenzionalmente disattivati
 * finché stock per giorno/fascia, prezzi contrattuali e conferma server
 * non saranno pronti; il menu non dichiara una disponibilità inesistente.
 */
export function initializePublicMenu(client) {
  const schoolInput = document.querySelector('#menu-school');
  const barInput = document.querySelector('#menu-bar');
  const searchInput = document.querySelector('#menu-search');
  const categoryList = document.querySelector('#menu-categories');
  const grid = document.querySelector('#menu-grid');
  const status = document.querySelector('#menu-status');
  const refreshButton = document.querySelector('#menu-refresh');
  let schools = [];
  let bars = [];
  let categories = [];
  let products = [];
  let selectedCategory = 'all';
  let requestId = 0;

  function feedback(message, isError = false) {
    status.textContent = message;
    status.dataset.type = isError ? 'error' : 'information';
  }
  function showEmpty(message) {
    grid.replaceChildren(make('p', 'menu-empty', message));
  }
  function fillSchools() {
    const previous = schoolInput.value;
    schoolInput.replaceChildren();
    for (const school of schools) schoolInput.add(new Option(school.name, school.id));
    if (schools.some((item) => item.id === previous)) schoolInput.value = previous;
  }
  function fillBars() {
    const previous = barInput.value;
    barInput.replaceChildren();
    for (const bar of barsForSchool(bars, schoolInput.value)) {
      barInput.add(new Option(bar.name, bar.id));
    }
    if ([...barInput.options].some((item) => item.value === previous)) barInput.value = previous;
  }
  function renderFilters() {
    categoryList.replaceChildren();
    const choices = [{ id:'all', name:'Tutti' }, ...categories.filter((item) => item.is_active)];
    for (const category of choices) {
      const button = make('button', 'menu-category-chip', category.name);
      button.type = 'button';
      button.setAttribute('aria-pressed', String(selectedCategory === category.id));
      button.addEventListener('click', () => {
        selectedCategory = category.id;
        renderFilters();
        renderProducts();
      });
      categoryList.append(button);
    }
  }
  function renderProducts() {
    const visible = filterPublicMenu(categories, products, {
      categoryId: selectedCategory, search: searchInput.value
    });
    grid.replaceChildren();
    if (!visible.length) {
      showEmpty(products.length
        ? 'Nessun prodotto corrisponde ai filtri scelti.'
        : 'Il bar non ha ancora pubblicato prodotti. Torna presto!');
      return;
    }
    for (const product of visible) {
      const card = make('article', 'menu-product-card');
      const categoryName = categories.find((category) => category.id === product.category_id)?.name || 'Prodotto';
      const badge = make('span', 'menu-product-category', categoryName);
      const title = make('h3', 'menu-product-title', product.name);
      const description = make('p', 'menu-product-description',
        product.description || 'Nessuna descrizione ancora disponibile.');
      const price = make('strong', 'menu-product-price', formatEuro(product.price_cents));
      if (product.image_path) {
        const photo=make('img','menu-product-image');
        photo.src=client.storage.from('breakapp-product-images').getPublicUrl(product.image_path).data.publicUrl;
        photo.alt='Foto di '+product.name;
        photo.loading='lazy';
        card.append(photo);
      }
      const ingredientInfo=make('p','menu-product-ingredients',
        product.ingredients ? 'Ingredienti: '+product.ingredients : 'Ingredienti non ancora indicati: chiedi al bar');
      const allergyInfo=make('p','menu-product-allergens',
        product.allergens?.length
          ? 'Allergeni dichiarati: '+product.allergens.map(x=>ALLERGEN_LABELS[x]||x).join(', ')
          : 'Allergeni non dichiarati: chiedi al bar prima di consumare');
      const details = make('button', 'button button-outline button-small', 'Dettagli e aggiungi');
      details.type = 'button';
      details.addEventListener('click', () => {
        window.dispatchEvent(new CustomEvent('breakapp:product-open', { detail: { id: product.id } }));
      });
      card.append(badge, title, description, ingredientInfo, allergyInfo, price, details);
      grid.append(card);
    }
  }
  async function fetchBarCatalog() {
    const token = ++requestId;
    selectedCategory = 'all';
    searchInput.value = '';
    categories = [];
    products = [];
    window.dispatchEvent(new CustomEvent('breakapp:catalog-ready', {
      detail: { schoolId: schoolInput.value, barId: barInput.value, products: [] }
    }));
    categoryList.replaceChildren();
    showEmpty('Caricamento del menu…');
    if (!barInput.value) {
      feedback('Nessun bar disponibile per la scuola selezionata.');
      showEmpty('Il menu non è disponibile per questa scuola.');
      return;
    }
    feedback('Caricamento del menu aggiornato da Supabase…');
    const barId = barInput.value;
    const schoolId = schoolInput.value;
    try {
      const [cat, pro] = await Promise.all([
        client.from('categories').select('id,name,sort_order,is_active')
          .eq('school_id',schoolId).eq('bar_id',barId).eq('is_active',true)
          .order('sort_order').order('name'),
        client.from('products').select('id,name,description,price_cents,category_id,is_active,ingredients,allergens,image_path')
          .eq('school_id',schoolId).eq('bar_id',barId).eq('is_active',true)
          .order('name')
      ]);
      if (token !== requestId) return;
      if (cat.error) throw cat.error;
      if (pro.error) throw pro.error;
      categories = cat.data || [];
      products = filterPublicMenu(categories, pro.data || []);
      window.dispatchEvent(new CustomEvent('breakapp:catalog-ready', {
        detail: { schoolId, barId, products }
      }));
      renderFilters();
      renderProducts();
      feedback(`Menu aggiornato · ${products.length} prodotti pubblicati.`);
    } catch (error) {
      if (token !== requestId) return;
      feedback(error?.message || 'Errore nel caricamento del menu.', true);
      showEmpty('Non è stato possibile caricare il menu. Riprova tra poco.');
    }
  }

  async function fetchDirectory() {
    if (!client) {
      schoolInput.disabled = true;
      barInput.disabled = true;
      searchInput.disabled = true;
      refreshButton.disabled = true;
      feedback('Il menu sarà disponibile quando Supabase sarà collegato.', true);
      showEmpty('Configurazione ancora in corso.');
      return;
    }
    feedback('Ricerca delle scuole attive…');
    try {
      const [schoolResponse, barResponse] = await Promise.all([
        client.from('schools').select('id,name').eq('is_active',true).order('name'),
        client.from('bars').select('id,school_id,name,is_active').eq('is_active',true).order('name')
      ]);
      if (schoolResponse.error) throw schoolResponse.error;
      if (barResponse.error) throw barResponse.error;
      schools = schoolResponse.data || [];
      bars = barResponse.data || [];
      fillSchools();
      fillBars();
      if (!schools.length) {
        feedback('Nessuna scuola attiva pubblicata.');
        showEmpty('Il servizio non è ancora disponibile.');
        return;
      }
      await fetchBarCatalog();
    } catch (error) {
      feedback(error?.message || 'Impossibile leggere le scuole.', true);
      showEmpty('Impossibile caricare il menu. Controlla la connessione e riprova.');
    }
  }

  schoolInput.addEventListener('change', () => { fillBars(); void fetchBarCatalog(); });
  barInput.addEventListener('change', () => { void fetchBarCatalog(); });
  searchInput.addEventListener('input', renderProducts);
  refreshButton.addEventListener('click', () => { void fetchDirectory(); });
  void fetchDirectory();
}
