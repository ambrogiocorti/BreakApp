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
  const placeLabel = document.querySelector('#menu-place-label');
  const placePicker = document.querySelector('#menu-place');
  const allergenLabel=make('label','menu-allergen-filter');
  allergenLabel.textContent='Nascondi i prodotti con';
  const allergenSelect=make('select','');
  allergenSelect.id='menu-allergen-exclude';
  allergenSelect.setAttribute('aria-label','Nascondi prodotti con allergene dichiarato');
  allergenSelect.add(new Option('Nessun filtro',''));
  for(const [id,label] of Object.entries(ALLERGEN_LABELS))allergenSelect.add(new Option(label,id));
  allergenLabel.append(allergenSelect);
  const allergenNote=make('p','menu-allergen-note',
    'Il filtro usa solo le dichiarazioni del bar: non garantisce l’assenza dell’allergene nei prodotti rimanenti. Se hai allergie, verifica ingredienti e possibili contaminazioni.');
  // The filter lives in a small panel: it is important, but not for everyone.
  const allergenPanel=make('details','menu-allergen-panel');
  const allergenSummary=make('summary','');
  const allergenState=make('span','status');allergenState.dataset.tone='warning';
  allergenSummary.append(make('span','summary-icon','⚠'),make('span','summary-text','Allergeni'),allergenState);
  allergenSummary.setAttribute('aria-label','Filtro allergeni');
  allergenSummary.querySelector('.summary-icon').setAttribute('aria-hidden','true');
  const allergenBody=make('div','menu-allergen-body');
  allergenBody.append(allergenLabel,allergenNote);
  allergenPanel.append(allergenSummary,allergenBody);
  document.querySelector('.menu-search').after(allergenPanel);
  let cartQuantities={},cartBar='';
  window.addEventListener('breakapp:cart-changed',event=>{
    cartQuantities=event.detail?.quantities||{};cartBar=event.detail?.barId||'';
    updateCardQuantities();
  });
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
  function updatePlace() {
    const schoolName=schoolInput.selectedOptions[0]?.text||'';
    const barName=barInput.selectedOptions[0]?.text||'';
    placeLabel.textContent=schoolName&&barName?barName+' · '+schoolName:schoolName||'Scegli scuola e bar';
    // Choosing is only needed when there is a real choice to make.
    const choice=schoolInput.options.length>1||barInput.options.length>1;
    placePicker.querySelector('.menu-place-change').hidden=!choice;
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
    const grouped=selectedCategory==='all'&&!searchInput.value.trim()&&categories.length>1;
    let lastCategory=null;
    if(grouped){
      const order=new Map(categories.map((category,index)=>[category.id,index]));
      visible.sort((a,b)=>(order.get(a.category_id)??999)-(order.get(b.category_id)??999));
    }
    for(const product of visible){
      if(grouped&&product.category_id!==lastCategory){
        lastCategory=product.category_id;
        grid.append(make('h2','menu-category-heading',categories.find(category=>category.id===product.category_id)?.name||'Altro'));
      }
      const card=make('article','menu-product-card');
      card.dataset.productId=product.id;
      const media=make('div','menu-product-media');
      if(product.image_path){
        const photo=make('img','');
        photo.src=client.storage.from('breakapp-product-images')
          .getPublicUrl(product.image_path).data.publicUrl;
        photo.alt='';photo.loading='lazy';
        media.append(photo);
      }else{
        media.textContent=String(product.name||'?').slice(0,1).toLocaleUpperCase('it-IT');
        media.dataset.tone=String(Math.max(0,categories.findIndex(category=>category.id===product.category_id))%4);
      }
      media.setAttribute('aria-hidden','true');
      const content=make('div','menu-product-content');
      const title=make('h3','menu-product-title',product.name);
      title.id='product-title-'+product.id;
      content.append(title);
      if(product.description)content.append(make('p','menu-product-description',product.description));
      const meta=make('p','menu-product-meta');
      meta.append(make('span','menu-product-price',formatEuro(product.price_cents)));
      const tags=make('span','menu-product-tags');
      const declared=Array.isArray(product.allergens)?product.allergens:[];
      if(declared.length){
        for(const code of declared.slice(0,3))
          tags.append(make('span','menu-product-tag',ALLERGEN_LABELS[code]||code));
        if(declared.length>3)
          tags.append(make('span','menu-product-tag','+'+(declared.length-3)));
      }else tags.append(make('span','menu-product-tag menu-product-tag--warning','Allergeni da chiedere'));
      meta.append(tags);content.append(meta);
      // The whole card opens the product sheet; the + stays a separate target.
      const details=make('button','menu-product-detail');
      details.type='button';
      details.setAttribute('aria-label',product.name+', '+formatEuro(product.price_cents)+': ingredienti e allergeni');
      details.addEventListener('click',()=>window.dispatchEvent(new CustomEvent('breakapp:product-open',{
        detail:{id:product.id}
      })));
      const action=make('div','menu-product-action');
      card.append(details,media,content,action);
      grid.append(card);
    }
    updateCardQuantities();
  }
  function updateCardQuantities(){
    for(const card of grid.querySelectorAll('.menu-product-card')){
      const id=card.dataset.productId,name=card.querySelector('.menu-product-title')?.textContent||'';
      const quantity=cartBar===barInput.value?Number(cartQuantities[id]||0):0;
      const action=card.querySelector('.menu-product-action');
      if(Number(action.dataset.quantity||-1)===quantity)continue;
      const hadFocus=action.contains(document.activeElement)?document.activeElement.dataset.role:null;
      action.dataset.quantity=String(quantity);card.dataset.inCart=String(quantity>0);
      action.replaceChildren();
      const add=()=>window.dispatchEvent(new CustomEvent('breakapp:quick-add',{detail:{id,barId:barInput.value}}));
      if(!quantity){
        const quickAdd=make('button','button button-primary menu-product-add','+');
        quickAdd.type='button';quickAdd.dataset.role='add';
        quickAdd.setAttribute('aria-label','Aggiungi '+name+' al carrello');
        quickAdd.title='Aggiungi al carrello';
        quickAdd.addEventListener('click',add);
        action.append(quickAdd);
      }else{
        const stepper=make('div','stepper');
        const less=make('button','','−');less.type='button';less.dataset.role='less';
        less.setAttribute('aria-label',(quantity===1?'Togli dal carrello: ':'Togli uno: ')+name);
        less.addEventListener('click',()=>window.dispatchEvent(new CustomEvent('breakapp:quick-set',{detail:{id,barId:barInput.value,quantity:quantity-1}})));
        const count=make('output','',String(quantity));count.setAttribute('aria-label',name+' nel carrello: '+quantity);
        const more=make('button','','+');more.type='button';more.dataset.role='add';
        more.setAttribute('aria-label','Aggiungi uno: '+name);
        more.addEventListener('click',add);
        stepper.append(less,count,more);action.append(stepper);
      }
      if(hadFocus)(action.querySelector('[data-role="'+hadFocus+'"]')||action.querySelector('button'))?.focus();
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
    updatePlace();
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
      feedback(products.length===1?'1 prodotto':products.length+' prodotti');
    } catch (error) {
      if (token !== requestId) return;
      feedback('Menu non disponibile. Controlla la connessione e usa «Aggiorna il menu».', true);
      showEmpty('Non è stato possibile caricare il menu. Riprova tra poco.');
    }
  }

  // Chi ha già una scuola (studente dopo la prima prenotazione, ospite,
  // personale) vede solo quella: il database rifiuta comunque le altre.
  async function ownSchoolId() {
    try {
      const { data: auth } = await client.auth.getUser();
      if (!auth?.user) return null;
      const r = await client.from('school_memberships').select('school_id').eq('user_id', auth.user.id).eq('membership_status', 'active');
      return !r.error && r.data?.length === 1 ? r.data[0].school_id : null;
    } catch { return null; }
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
      const [schoolResponse, barResponse, ownSchool] = await Promise.all([
        client.from('schools').select('id,name').eq('is_active',true).order('name'),
        client.from('bars').select('id,school_id,name,is_active').eq('is_active',true).order('name'),
        ownSchoolId()
      ]);
      if (schoolResponse.error) throw schoolResponse.error;
      if (barResponse.error) throw barResponse.error;
      schools = restrictToOwnSchool(schoolResponse.data || [], ownSchool);
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
      feedback('Scuole non disponibili. Controlla la connessione e riprova.', true);
      showEmpty('Impossibile caricare il menu. Controlla la connessione e riprova.');
    }
  }

  schoolInput.addEventListener('change', () => {
    remember('breakapp-menu-school',schoolInput.value);
    fillBars();remember('breakapp-menu-bar-'+schoolInput.value,barInput.value);
    void fetchBarCatalog();
  });
  barInput.addEventListener('change', () => {
    placePicker.open=false;
    remember('breakapp-menu-bar-'+schoolInput.value,barInput.value);
    void fetchBarCatalog();
  });
  searchInput.addEventListener('input', renderProducts);
  allergenSelect.addEventListener('change',()=>{
    allergenState.textContent=allergenSelect.value?'Senza '+ALLERGEN_LABELS[allergenSelect.value].toLocaleLowerCase('it-IT'):'';
    renderProducts();
  });
  refreshButton.addEventListener('click', () => { void fetchDirectory(); });
  void fetchDirectory();
  // Dopo l'accesso o il cambio di account l'elenco delle scuole può cambiare.
  let lastUser;
  client?.auth?.onAuthStateChange?.((_event, session) => {
    const id = session?.user?.id || null;
    const first = lastUser === undefined;
    if (id === lastUser) return;
    lastUser = id;
    if (first) return; // il primo caricamento è già in corso
    queueMicrotask(() => { void fetchDirectory(); });
  });
}

export function restrictToOwnSchool(schools, ownSchool) {
  if (!ownSchool) return schools;
  const own = schools.filter((school) => school.id === ownSchool);
  return own.length ? own : schools;
}
