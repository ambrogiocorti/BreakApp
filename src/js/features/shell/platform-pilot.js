import { parseWeeklyPeriods, formatWeeklyPeriods, WEEKDAY_LABELS } from '../operations/calendar-core.js';
import { parseEuroToCents, formatEuro } from '../catalog/utils.js';

const $=id=>document.getElementById(id);
const textNode=(tag,text='',cls='')=>{const x=document.createElement(tag);x.textContent=text;x.className=cls;return x;};
const allergens=[
 ['gluten','Cereali con glutine'],['crustaceans','Crostacei'],['eggs','Uova'],['fish','Pesce'],
 ['peanuts','Arachidi'],['soy','Soia'],['milk','Latte'],['nuts','Frutta a guscio'],
 ['celery','Sedano'],['mustard','Senape'],['sesame','Sesamo'],['sulphites','Solfiti'],
 ['lupin','Lupini'],['molluscs','Molluschi']
];
const todayRome=()=>new Intl.DateTimeFormat('en-CA',{
 timeZone:'Europe/Rome',year:'numeric',month:'2-digit',day:'2-digit'
}).format(new Date());

export function initializePlatformPilot(client){
 if(!client)return;
 const section=$('platform-pilot-tools'),status=$('pilot-status'),
  schoolSelect=$('pilot-school'),barSelect=$('pilot-bar'),
  staffList=$('pilot-staff-list'),hoursList=$('pilot-hours-list'),
  windowsList=$('pilot-windows-list'),stockSummary=$('pilot-stock-summary'),
  readiness=$('pilot-readiness');
 let allowed=false,schools=[],bars=[],products=[],categories=[],staff=[],hours=[],windows=[],stocks=[],token=0;
 let currentUser=null,authEpoch=0;
 let requestedSchool=null,refreshEpoch=0;
 const tabs=[...$('pilot-tabs').querySelectorAll('[role="tab"]')];
 function activateTab(selected,focus=false){
   for(const tab of tabs){const active=tab===selected;tab.setAttribute('aria-selected',String(active));tab.tabIndex=active?0:-1;$(tab.getAttribute('aria-controls')).hidden=!active;}
   if(focus)selected.focus();
 }
 tabs.forEach((tab,index)=>{
   tab.addEventListener('click',()=>activateTab(tab));
   tab.addEventListener('keydown',event=>{
     const next=event.key==='ArrowRight'?(index+1)%tabs.length:event.key==='ArrowLeft'?(index+tabs.length-1)%tabs.length:event.key==='Home'?0:event.key==='End'?tabs.length-1:null;
     if(next!==null){event.preventDefault();activateTab(tabs[next],true);}
   });
 });

 for(const [id] of [['pilot-window-date'],['pilot-stock-date']]){
   $(id).value=todayRome();
 }
 const checklist=$('pilot-allergens');
 for(const [code,label] of allergens){
   const wrapper=textNode('label','', 'pilot-allergen-label');
   const check=document.createElement('input');check.type='checkbox';check.value=code;
   wrapper.append(check,textNode('span',label));checklist.append(wrapper);
 }
 const productAllergens=$('pilot-product-allergens');
 for(const [code,label] of allergens){
   const wrapper=textNode('label','','pilot-allergen-label');
   const check=document.createElement('input');check.type='checkbox';check.value=code;
   wrapper.append(check,textNode('span',label));productAllergens.append(wrapper);
 }
 const say=(msg,error=false)=>{status.textContent=msg;status.dataset.type=error?'error':'information';};
 const stripeButton=$('pilot-stripe-onboarding'),stripeFeedback=$('pilot-stripe-feedback');
 stripeButton.addEventListener('click',async()=>{
   if(!allowed||stripeButton.disabled)return;
   stripeButton.disabled=true;
   stripeFeedback.textContent='Generazione del link sicuro Stripe…';
   stripeFeedback.dataset.type='information';
   try{
     const {data,error}=await client.functions.invoke('stripe-connect-onboarding',{body:{}});
     if(error){
       let reason=error.message||'Link non disponibile';
       try{
         const payload=await error.context?.json();
         if(typeof payload?.error==='string')reason=payload.error;
         if(typeof payload?.stripe_code==='string')reason+=' (codice Stripe: '+payload.stripe_code+')';
         if(typeof payload?.stripe_request_id==='string')reason+=' · Riferimento: '+payload.stripe_request_id;
       }catch{/* The response body might not be JSON. */}
       throw new Error(reason);
     }
     if(data?.error)throw new Error(data.error);
     const destination=new URL(data.onboarding_url);
     if(destination.protocol!=='https:'||
       !(destination.hostname==='stripe.com'||destination.hostname.endsWith('.stripe.com')))
       throw new Error('Indirizzo di attivazione non valido');
     stripeFeedback.textContent='Reindirizzamento verso Stripe…';
     window.location.assign(destination.href);
   }catch(error){
     stripeFeedback.dataset.type='error';
     stripeFeedback.textContent='Impossibile avviare Stripe: '+error.message;
     stripeButton.disabled=false;
   }
 });
 const school=()=>schools.find(s=>s.id===schoolSelect.value);
 const bar=()=>bars.find(b=>b.id===barSelect.value);
 function replaceOptions(select,items,selected){
   select.replaceChildren();
   for(const [value,label] of items)select.add(new Option(label,value));
   if(items.some(x=>x[0]===selected))select.value=selected;
 }
 function updateSchool(){
   const b=bars.filter(b=>b.school_id===schoolSelect.value&&b.is_active);
   const old=barSelect.value;
   replaceOptions(barSelect,b.map(x=>[x.id,x.name]),old);
   void updateBar();
 }
 async function fetchSchoolStaff(expectedToken){
   const current=school();
   if(!current)return [];
   const {data,error}=await client.rpc('platform_list_school_staff',{p_school_id:current.id});
   if(expectedToken!==token||!allowed)return [];
   if(error)throw error;
   staff=Array.isArray(data)?data:[];
   staffList.replaceChildren();
   if(!staff.length)staffList.append(textNode('p','Nessun operatore scolastico assegnato.'));
   for(const member of staff){
     const row=textNode('div','','pilot-staff-row');
     const info=textNode('div','','pilot-staff-info');
     const roles={school_admin:'Admin scuola',bartender:'Barista',warehouse_manager:'Magazziniere'};
     info.append(textNode('strong',member.email),
       textNode('span',(roles[member.role]||member.role)+' · '+member.status));
     const remove=textNode('button','Revoca','button button-outline button-small');
     remove.type='button';
     remove.addEventListener('click',async()=>{
       if(!confirm('Revocare il ruolo '+(roles[member.role]||member.role)+
         ' a '+member.email+' per '+current.name+'?'))return;
       remove.disabled=true;
       const {error:e}=await client.rpc('platform_revoke_school_staff',{
         p_school_id:current.id,p_user_id:member.user_id,p_role:member.role
       });
       if(e){say(e.message,true);remove.disabled=false;return;}
       say('Ruolo revocato sul server.');await refresh();
     });
     row.append(info,remove);staffList.append(row);
   }
   return staff;
 }
 function renderHours(){
   hoursList.replaceChildren();
   for(let n=1;n<=7;n++){
     const day=n%7,periods=hours.filter(x=>x.weekday===day);
     const row=textNode('div',WEEKDAY_LABELS[day]+': '+formatWeeklyPeriods(periods),'service-list-item');
     hoursList.append(row);
   }
   const selected=Number($('pilot-weekday').value);
   $('pilot-periods').value=hours.filter(x=>x.weekday===selected)
     .map(x=>x.starts_at.slice(0,5)+'-'+x.ends_at.slice(0,5)).join('\n');
 }
 function renderWindows(){
   windowsList.replaceChildren();
   const sorted=windows.filter(w=>w.is_active)
     .sort((a,b)=>(a.service_date+a.starts_at).localeCompare(b.service_date+b.starts_at));
   if(!sorted.length)windowsList.append(textNode('p','Nessuna fascia attiva configurata.'));
   for(const w of sorted.slice(0,30))
     windowsList.append(textNode('div',
       w.service_date+' · '+w.starts_at.slice(0,5)+'–'+w.ends_at.slice(0,5),
       'service-list-item'));
 }
 function renderCatalog(){
   const catEdit=$('pilot-category-edit'),productEdit=$('pilot-product-edit');
   const oldCategory=catEdit.value,oldProduct=productEdit.value;
   replaceOptions(catEdit,[['','Nuova categoria'],...categories.map(x=>[x.id,x.name])],oldCategory);
   replaceOptions(productEdit,[['','Nuovo prodotto'],...products.map(x=>[x.id,x.name])],oldProduct);
   replaceOptions($('pilot-product-category'),
     categories.filter(x=>x.is_active).map(x=>[x.id,x.name]),
     $('pilot-product-category').value);
   const catList=$('pilot-category-list'),productList=$('pilot-product-list');
   catList.replaceChildren();productList.replaceChildren();
   if(!categories.length)catList.append(textNode('p','Non ci sono ancora categorie.'));
   for(const category of categories){
     const row=textNode('div','','service-list-item');
     row.append(textNode('strong',category.name),
       textNode('span',category.is_active?'Visibile':'Nascosta'));
     catList.append(row);
   }
   if(!products.length)productList.append(textNode('p','Non ci sono ancora prodotti.'));
   for(const p of products){
     const row=textNode('div','','service-list-item');
     row.append(textNode('strong',p.name+' · '+formatEuro(p.price_cents)),
       textNode('span',(p.is_active?'Pubblicato':'Non pubblicato')+
         ' · '+(categories.find(c=>c.id===p.category_id)?.name||'Categoria assente')));
     productList.append(row);
   }
   fillSelectedCategory();fillSelectedProduct();
 }
 function fillSelectedCategory(){
   const c=categories.find(c=>c.id===$('pilot-category-edit').value);
   $('pilot-category-name').value=c?.name||'';
   $('pilot-category-active').checked=c?.is_active??true;
 }
 function fillSelectedProduct(){
   const p=products.find(p=>p.id===$('pilot-product-edit').value);
   $('pilot-product-category').value=p?.category_id||
     $('pilot-product-category').options[0]?.value||'';
   $('pilot-product-name').value=p?.name||'';
   $('pilot-product-description').value=p?.description||'';
   $('pilot-product-price').value=p?String(p.price_cents/100).replace('.',','):'';
   $('pilot-product-ingredients').value=p?.ingredients||'';
   $('pilot-product-active').checked=p?.is_active??true;
   $('pilot-product-image').value='';
   productAllergens.querySelectorAll('input[type="checkbox"]').forEach(x=>{
     x.checked=Boolean(p?.allergens?.includes(x.value));
   });
 }
 function renderProducts(){
   replaceOptions($('pilot-stock-product'),products.map(p=>[p.id,p.name]),
    $('pilot-stock-product').value);
   replaceOptions($('pilot-food-product'),products.map(p=>[p.id,p.name]),
    $('pilot-food-product').value);
   renderFood();
   renderStock();
 }
 function renderFood(){
   const p=products.find(p=>p.id===$('pilot-food-product').value);
   $('pilot-ingredients').value=p?.ingredients||'';
   checklist.querySelectorAll('input[type="checkbox"]').forEach(c=>{
     c.checked=Boolean(p?.allergens?.includes(c.value));
   });
 }
 function renderStock(){
   stockSummary.replaceChildren();
   const date=$('pilot-stock-date').value;
   const scoped=stocks.filter(s=>s.service_date===date);
   if(!scoped.length)stockSummary.append(textNode('p','Nessuna disponibilità registrata per il giorno.'));
   for(const s of scoped){
     const p=products.find(p=>p.id===s.product_id);
     stockSummary.append(textNode('div',
       (p?.name||'Prodotto')+': '+(s.capacity===null?'illimitata':s.capacity)+
       ' unità totali, '+s.allocated+' già allocate','service-list-item'));
   }
   const current=stocks.find(s=>s.service_date===date&&
    s.product_id===$('pilot-stock-product').value);
   $('pilot-stock-capacity').value=current?.capacity??'';
 }
 function renderReadiness(){
   readiness.replaceChildren();
   const selected=school(),active=windows.filter(w=>w.is_active&&w.service_date>=todayRome());
   const periods=hours.length,source=products.filter(p=>p.is_active);
   const hasStock=active.some(w=>stocks.some(s=>s.service_date===w.service_date&&
     source.some(p=>p.id===s.product_id)));
   const checks=[
     ['Posizione scuola',Boolean(selected?.latitude!=null&&selected?.longitude!=null)],
     ['Almeno un prodotto attivo',source.length>0],
     ['Ingredienti dei prodotti attivi',source.length>0&&source.every(p=>Boolean(p.ingredients?.trim()))],
     ['Orari settimanali',periods>0],
     ['Fasce future prenotabili',active.length>0],
     ['Scorte per le fasce disponibili',hasStock],
     ['Almeno un Barista assegnato',staff.some(m=>m.role==='bartender'&&m.status==='active')],
     ['Almeno un Admin scuola assegnato',staff.some(m=>m.role==='school_admin'&&m.status==='active')]
   ];
   for(const [label,ok] of checks){
     const row=textNode('div', (ok?'✓ ':'○ ')+label,'pilot-check'+(ok?' is-ready':''));
     readiness.append(row);
   }
   const all=checks.every(c=>c[1]);
   $('pilot-readiness-count').textContent=checks.filter(c=>c[1]).length+'/'+checks.length;
   const msg=textNode('strong',all?
    'Configurazione preliminare completa: procedi ai test reali con Cliente e Barista.':
    'Configurazione incompleta: i controlli mancanti sono indicati qui sopra.');
   readiness.prepend(msg);
 }
 async function updateBar(){
   const myToken=++token;
   const b=bar();products=[];categories=[];hours=[];windows=[];stocks=[];staff=[];
   if(!b){renderCatalog();renderProducts();renderWindows();renderHours();renderReadiness();return;}
   say('Caricamento della configurazione…');
   const [p,c,h,w,st]=await Promise.all([
     client.from('products').select('id,category_id,name,description,price_cents,ingredients,allergens,image_path,is_active')
       .eq('school_id',b.school_id).eq('bar_id',b.id).order('name'),
     client.from('categories').select('id,name,is_active')
       .eq('school_id',b.school_id).eq('bar_id',b.id).order('name'),
     client.from('bar_opening_hours').select('weekday,starts_at,ends_at')
       .eq('school_id',b.school_id).eq('bar_id',b.id).order('weekday').order('starts_at'),
     client.from('pickup_windows').select('id,service_date,starts_at,ends_at,is_active')
       .eq('school_id',b.school_id).eq('bar_id',b.id)
       .gte('service_date',todayRome()).order('service_date').order('starts_at').limit(100),
     client.from('daily_stock').select('product_id,service_date,capacity,allocated')
       .eq('school_id',b.school_id).eq('bar_id',b.id)
       .gte('service_date',todayRome()).order('service_date').limit(200)
   ]);
   if(myToken!==token)return;
   const error=p.error||c.error||h.error||w.error||st.error;
   if(error){say('Lettura configurazione fallita: '+error.message,true);return;}
   products=p.data||[];categories=c.data||[];hours=h.data||[];windows=w.data||[];stocks=st.data||[];
   try{await fetchSchoolStaff(myToken);}catch(err){if(myToken===token)say(err.message,true);return;}
   if(myToken!==token)return;
   renderHours();renderWindows();renderCatalog();renderProducts();renderReadiness();
   say('Configurazione aggiornata.');
 }
 async function refresh(){
   if(!allowed)return;
   const refreshToken=++refreshEpoch,selected=requestedSchool||school()?.id;
   const currentBar=bar()?.id;
   const [s,b]=await Promise.all([
     client.from('schools').select('id,name,is_active,latitude,longitude').eq('is_active',true).order('name'),
     client.from('bars').select('id,name,school_id,is_active').eq('is_active',true).order('name')
   ]);
   if(refreshToken!==refreshEpoch||!allowed)return;
   if(s.error||b.error){say((s.error||b.error).message,true);return;}
   schools=s.data||[];bars=b.data||[];
   replaceOptions(schoolSelect,schools.map(x=>[x.id,x.name]),selected);
   requestedSchool=null;
   updateSchool();
   if(currentBar&&bars.some(x=>x.id===currentBar&&x.school_id===schoolSelect.value)){
     barSelect.value=currentBar;void updateBar();
   }
 }
 async function run(form,callback){
   if(!allowed||!form.reportValidity())return;
   const button=form.querySelector('button[type="submit"]');
   button.disabled=true;
   try{await callback();await refresh();}
   catch(err){say(err.message||'Operazione non riuscita.',true);}
   finally{button.disabled=false;}
 }
 $('pilot-category-edit').addEventListener('change',fillSelectedCategory);
 $('pilot-product-edit').addEventListener('change',fillSelectedProduct);
 $('pilot-category-form').addEventListener('submit',event=>{
   event.preventDefault();void run(event.currentTarget,async()=>{
     const {error}=await client.rpc('platform_save_category',{
       p_bar_id:barSelect.value,
       p_category_id:$('pilot-category-edit').value||null,
       p_name:$('pilot-category-name').value.trim(),
       p_active:$('pilot-category-active').checked
     });
     if(error)throw error;
     say('Categoria salvata su Supabase.');
   });
 });
 $('pilot-product-form').addEventListener('submit',event=>{
   event.preventDefault();void run(event.currentTarget,async()=>{
     const b=bar(),school=schools.find(s=>s.id===b?.school_id);
     if(!b||!school)throw new Error('Seleziona il bar prima di salvare il prodotto.');
     const file=$('pilot-product-image').files[0]||null;
     const ext={'image/jpeg':'jpg','image/png':'png','image/webp':'webp'}[file?.type];
     if(file&&(!ext||file.size>2097152||file.size<=0))
       throw new Error('Fotografia non valida: JPG, PNG o WebP fino a 2 MB.');
     const allergensSelected=[...productAllergens.querySelectorAll('input:checked')].map(x=>x.value);
     const {data:id,error}=await client.rpc('platform_save_product',{
       p_bar_id:b.id,p_product_id:$('pilot-product-edit').value||null,
       p_category_id:$('pilot-product-category').value,
       p_name:$('pilot-product-name').value.trim(),
       p_description:$('pilot-product-description').value.trim(),
       p_price_cents:parseEuroToCents($('pilot-product-price').value),
       p_ingredients:$('pilot-product-ingredients').value.trim(),
       p_allergens:allergensSelected,p_active:$('pilot-product-active').checked
     });
     if(error)throw error;
     if(file){
       const path=school.id+'/'+b.id+'/'+crypto.randomUUID()+'.'+ext;
       const upload=await client.storage.from('breakapp-product-images')
         .upload(path,file,{contentType:file.type,upsert:false});
       if(upload.error){
         say('Prodotto salvato. Caricamento fotografia fallito: '+upload.error.message,true);
         return;
       }
       const link=await client.rpc('platform_set_product_image',{
         p_bar_id:b.id,p_product_id:id,p_object_path:path
       });
       if(link.error){
         say('Prodotto salvato; foto caricata ma non associata: '+link.error.message,true);
         return;
       }
     }
     say('Prodotto, prezzo e ingredienti salvati su Supabase.');
   });
 });
  $('pilot-staff-form').addEventListener('submit',event=>{
   event.preventDefault();void run(event.currentTarget,async()=>{
     const {error}=await client.rpc('platform_assign_school_staff',{
       p_school_id:schoolSelect.value,
       p_email:$('pilot-staff-email').value.trim(),
       p_role:$('pilot-staff-role').value
     });
     if(error)throw error;
     $('pilot-staff-email').value='';
     say('Ruolo assegnato e registrato sul database. Il nuovo operatore può accedere con il proprio account.');
   });
 });
 $('pilot-hours-form').addEventListener('submit',event=>{
   event.preventDefault();void run(event.currentTarget,async()=>{
     const periods=parseWeeklyPeriods($('pilot-periods').value);
     const {error}=await client.rpc('set_bar_weekly_hours',{
       p_bar_id:barSelect.value,p_weekday:Number($('pilot-weekday').value),
       p_periods:periods
     });
     if(error)throw error;
     say('Orari settimanali aggiornati.');
   });
 });
 $('pilot-window-form').addEventListener('submit',event=>{
   event.preventDefault();void run(event.currentTarget,async()=>{
     const {error}=await client.rpc('platform_create_pickup_window',{
       p_bar_id:barSelect.value,p_date:$('pilot-window-date').value,
       p_start:$('pilot-window-start').value,p_end:$('pilot-window-end').value
     });
     if(error)throw error;
     say('Fascia di ritiro creata sul server.');
   });
 });
 $('pilot-stock-form').addEventListener('submit',event=>{
   event.preventDefault();void run(event.currentTarget,async()=>{
     const raw=$('pilot-stock-capacity').value.trim();
     const cap=raw===''?null:Number(raw);
     if(cap!==null&&(!Number.isSafeInteger(cap)||cap<0))throw new Error('Quantità non valida');
     const {error}=await client.rpc('platform_set_stock',{
       p_bar_id:barSelect.value,p_product_id:$('pilot-stock-product').value,
       p_date:$('pilot-stock-date').value,p_capacity:cap
     });
     if(error)throw error;
     say('Scorte salvate senza modificare le quantità già allocate.');
   });
 });
 $('pilot-food-form').addEventListener('submit',event=>{
   event.preventDefault();void run(event.currentTarget,async()=>{
     const selected=[...checklist.querySelectorAll('input:checked')].map(x=>x.value);
     const {error}=await client.rpc('platform_set_product_foodinfo',{
       p_product_id:$('pilot-food-product').value,
       p_ingredients:$('pilot-ingredients').value.trim(),p_allergens:selected
     });
     if(error)throw error;
     say('Ingredienti e allergeni aggiornati nel catalogo.');
   });
 });
 schoolSelect.addEventListener('change',updateSchool);
 barSelect.addEventListener('change',()=>void updateBar());
 $('pilot-weekday').addEventListener('change',renderHours);
 $('pilot-stock-date').addEventListener('change',renderStock);
 $('pilot-stock-product').addEventListener('change',renderStock);
 $('pilot-food-product').addEventListener('change',renderFood);
 $('pilot-reload').addEventListener('click',()=>void refresh());
 window.addEventListener('breakapp:platform-open-school',event=>{
   if(!allowed)return;requestedSchool=event.detail?.schoolId;
   activateTab(tabs[0]);void refresh();
 });
 window.addEventListener('breakapp:platform-school-updated',()=>{if(allowed)void refresh();});
 window.addEventListener('breakapp:platform-onboarded',event=>{if(allowed){requestedSchool=event.detail?.school_id||null;void refresh();}});

 async function enter(){
   const seq=++authEpoch;
   // A workspace context can arrive before this module's initial getUser().
   // Always validate the session now, never let an older async result re-open UI.
   const session=await client.auth.getUser();
   if(seq!==authEpoch)return;
   currentUser=!session.error?session.data?.user||null:null;
   if(!currentUser){
     allowed=false;stripeButton.disabled=true;section.hidden=true;return;
   }
   const [role,level]=await Promise.all([
     client.rpc('is_current_platform_admin'),
     client.auth.mfa.getAuthenticatorAssuranceLevel()
   ]);
   if(seq!==authEpoch)return;
   allowed=!role.error&&role.data===true&&!level.error&&level.data?.currentLevel==='aal2';
   stripeButton.disabled=!allowed;
   section.hidden=!allowed;
   if(allowed)await refresh();
   else say('Pannello disponibile solo al Super Admin con 2FA verificata.',true);
 }
 window.addEventListener('breakapp:workspace-context',event=>{
   if(event.detail?.role==='platform_admin')void enter();
   else {authEpoch++;refreshEpoch++;token++;allowed=false;stripeButton.disabled=true;section.hidden=true;}
 });
 client.auth.onAuthStateChange((_e,session)=>queueMicrotask(()=>{
   currentUser=session?.user||null;
   if(!currentUser){authEpoch++;refreshEpoch++;token++;allowed=false;section.hidden=true;schools=[];bars=[];}
 }));
 client.auth.getUser().then(({data,error})=>{if(!error)currentUser=data?.user||null;});
}
