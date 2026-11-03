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

/** Public menu: checkout prices and inventory remain server-authoritative. */
export function initializePublicMenu(client) {
  const schoolInput = document.querySelector('#menu-school');
  const barInput = document.querySelector('#menu-bar');
  const searchInput = document.querySelector('#menu-search');
  const categoryList = document.querySelector('#menu-categories');
  const grid = document.querySelector('#menu-grid');
  const status = document.querySelector('#menu-status');
  const refreshButton = document.querySelector('#menu-refresh');
  const allergenLabel=make('label','menu-allergen-filter');
  allergenLabel.textContent='Nascondi prodotti che dichiarano:';
  const allergenSelect=make('select','');
  allergenSelect.id='menu-allergen-exclude';
  allergenSelect.setAttribute('aria-label','Nascondi prodotti con allergene dichiarato');
  allergenSelect.add(new Option('Nessun filtro allergeni',''));
  for(const [id,label] of Object.entries(ALLERGEN_LABELS))allergenSelect.add(new Option(label,id));
  allergenLabel.append(allergenSelect);
  const allergenNote=make('p','menu-allergen-note',
    'Il filtro usa solo le dichiarazioni del bar: non garantisce l’assenza dell’allergene nei prodotti rimanenti. Se hai allergie, verifica ingredienti e possibili contaminazioni.');
  categoryList.after(allergenLabel,allergenNote);
  const preference=key=>{try{return localStorage.getItem(key)||'';}catch{return '';}};
  const remember=(key,value)=>{try{localStorage.setItem(key,value);}catch{/* Private browsing */}};

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
    const saved=preference('breakapp-menu-school');
    if(schools.some(item=>item.id===previous))schoolInput.value=previous;
    else if(schools.some(item=>item.id===saved))schoolInput.value=saved;
  }
  function fillBars() {
    const previous = barInput.value;
    barInput.replaceChildren();
    for (const bar of barsForSchool(bars, schoolInput.value)) {
      barInput.add(new Option(bar.name, bar.id));
    }
    const saved=preference('breakapp-menu-bar-'+schoolInput.value);
    if([...barInput.options].some(item=>item.value===previous))barInput.value=previous;
    else if([...barInput.options].some(item=>item.value===saved))barInput.value=saved;
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
    const visible=filterPublicMenu(categories,products,{
      categoryId:selectedCategory,search:searchInput.value,
      excludeDeclaredAllergen:allergenSelect.value
    });
    grid.replaceChildren();
    if(!visible.length){
      showEmpty(products.length?'Nessun prodotto corrisponde ai filtri scelti.':
        'Il bar non ha ancora pubblicato prodotti. Torna presto!');
      return;
    }
    for(const product of visible){
      const card=make('article','menu-product-card');
      const media=make('div','menu-product-media');
      if(product.image_path){
        const photo=make('img','');
        photo.src=client.storage.from('breakapp-product-images')
          .getPublicUrl(product.image_path).data.publicUrl;
        photo.alt='Foto di '+product.name;photo.loading='lazy';
        media.append(photo);
      }else{
        media.textContent=String(product.name||'?').slice(0,1).toLocaleUpperCase('it-IT');
        media.setAttribute('aria-hidden','true');
      }
      const content=make('div','menu-product-content');
      const categoryName=categories.find(category=>category.id===product.category_id)?.name||'Prodotto';
      content.append(make('span','menu-product-category',categoryName),
        make('h3','menu-product-title',product.name),
        make('strong','menu-product-price',formatEuro(product.price_cents)));
      if(product.description)content.append(make('p','menu-product-description',product.description));
      const tags=make('div','menu-product-tags');
      const declared=Array.isArray(product.allergens)?product.allergens:[];
      if(declared.length){
        for(const code of declared.slice(0,2))
          tags.append(make('span','menu-product-tag',ALLERGEN_LABELS[code]||code));
        if(declared.length>2)
          tags.append(make('span','menu-product-tag','+'+(declared.length-2)+' allergeni'));
      }else tags.append(make('span','menu-product-tag menu-product-tag--warning','Allergeni: chiedi al bar'));
      content.append(tags);
      const details=make('button','menu-product-detail','Ingredienti e dettagli');
      details.type='button';
      details.setAttribute('aria-label','Dettagli di '+product.name);
      details.addEventListener('click',()=>window.dispatchEvent(new CustomEvent('breakapp:product-open',{
        detail:{id:product.id}
      })));
      content.append(details);
      const quickAdd=make('button','button button-primary menu-product-add','+');
      quickAdd.type='button';
      quickAdd.setAttribute('aria-label','Aggiungi '+product.name+' al carrello');
      quickAdd.title='Aggiungi al carrello';
      quickAdd.addEventListener('click',()=>window.dispatchEvent(new CustomEvent('breakapp:quick-add',{
        detail:{id:product.id,barId:barInput.value}
      })));
      card.append(media,content,quickAdd);
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
    feedback('Caricamento dei prodotti…');
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

  schoolInput.addEventListener('change', () => {
    remember('breakapp-menu-school',schoolInput.value);
    fillBars();remember('breakapp-menu-bar-'+schoolInput.value,barInput.value);
    void fetchBarCatalog();
  });
  barInput.addEventListener('change', () => {
    remember('breakapp-menu-bar-'+schoolInput.value,barInput.value);
    void fetchBarCatalog();
  });
  searchInput.addEventListener('input', renderProducts);
  allergenSelect.addEventListener('change',renderProducts);
  refreshButton.addEventListener('click', () => { void fetchDirectory(); });
  void fetchDirectory();
}
