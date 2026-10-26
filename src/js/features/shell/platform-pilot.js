import { parseWeeklyPeriods, formatWeeklyPeriods, WEEKDAY_LABELS } from '../operations/calendar-core.js';

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
 let allowed=false,schools=[],bars=[],products=[],staff=[],hours=[],windows=[],stocks=[],token=0;
 let currentUser=null;

 for(const [id] of [['pilot-window-date'],['pilot-stock-date']]){
   $(id).value=todayRome();
 }
 const checklist=$('pilot-allergens');
 for(const [code,label] of allergens){
   const wrapper=textNode('label','', 'pilot-allergen-label');
   const check=document.createElement('input');check.type='checkbox';check.value=code;
   wrapper.append(check,textNode('span',label));checklist.append(wrapper);
 }
 const say=(msg,error=false)=>{status.textContent=msg;status.dataset.type=error?'error':'information';};
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
 async function fetchSchoolStaff(){
   const current=school();
   if(!current)return [];
   const {data,error}=await client.rpc('platform_list_school_staff',{p_school_id:current.id});
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
   const msg=textNode('strong',all?
    'Configurazione preliminare completa: procedi ai test reali con Cliente e Barista.':
    'Configurazione incompleta: i controlli mancanti sono indicati qui sopra.');
   readiness.prepend(msg);
 }
 async function updateBar(){
   const b=bar();products=[];hours=[];windows=[];stocks=[];staff=[];
   if(!b){renderProducts();renderWindows();renderHours();renderReadiness();return;}
   const myToken=++token;
   say('Verifica impostazioni e registrazioni su Supabase…');
   const [p,h,w,st]=await Promise.all([
     client.from('products').select('id,name,ingredients,allergens,is_active')
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
   const error=p.error||h.error||w.error||st.error;
   if(error){say('Lettura configurazione fallita: '+error.message,true);return;}
   products=p.data||[];hours=h.data||[];windows=w.data||[];stocks=st.data||[];
   try{await fetchSchoolStaff();}catch(err){say(err.message,true);return;}
   if(myToken!==token)return;
   renderHours();renderWindows();renderProducts();renderReadiness();
   say('Dati operativi verificati sul progetto BreakApp.');
 }
 async function refresh(){
   if(!allowed)return;
   const selected=school()?.id;
   const currentBar=bar()?.id;
   const [s,b]=await Promise.all([
     client.from('schools').select('id,name,is_active,latitude,longitude').eq('is_active',true).order('name'),
     client.from('bars').select('id,name,school_id,is_active').eq('is_active',true).order('name')
   ]);
   if(s.error||b.error){say((s.error||b.error).message,true);return;}
   schools=s.data||[];bars=b.data||[];
   replaceOptions(schoolSelect,schools.map(x=>[x.id,x.name]),selected);
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

 async function enter(){
   if(!currentUser)return;
   const [role,level]=await Promise.all([
     client.rpc('is_current_platform_admin'),
     client.auth.mfa.getAuthenticatorAssuranceLevel()
   ]);
   allowed=!role.error&&role.data===true&&!level.error&&level.data?.currentLevel==='aal2';
   section.hidden=!allowed;
   if(allowed)await refresh();
   else say('Pannello disponibile solo al Super Admin con 2FA verificata.',true);
 }
 window.addEventListener('breakapp:workspace-context',event=>{
   if(event.detail?.role==='platform_admin')void enter();
   else {allowed=false;section.hidden=true;}
 });
 client.auth.onAuthStateChange((_e,session)=>queueMicrotask(()=>{
   currentUser=session?.user||null;
   if(!currentUser){token++;allowed=false;section.hidden=true;schools=[];bars=[];}
 }));
 client.auth.getUser().then(({data,error})=>{if(!error)currentUser=data?.user||null;});
}
