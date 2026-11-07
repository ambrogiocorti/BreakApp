import { loadSchoolAccess } from '../auth/access.js';
import {icon} from '../../core/icons.js';

// A new screen opens at its top. Dashboards fill in asynchronously, and WebKit
// can move the window a few pixels as that late content lands. Keep the page
// pinned to the top for a moment, unless the person starts scrolling.
let releaseTop=null;
function holdTop(stillActive,reset){
 releaseTop?.();
 const stop=()=>{clearTimeout(timer);removeEventListener('scroll',onScroll);for(const t of USER_SCROLL)removeEventListener(t,stop,true);releaseTop=null;};
 const onScroll=()=>{const a=document.activeElement;if(stillActive()&&scrollY!==0&&(!a||a===document.body||a.id==='workspace-page-title'))reset();};
 const timer=setTimeout(stop,1500);
 addEventListener('scroll',onScroll,{passive:true});
 for(const t of USER_SCROLL)addEventListener(t,stop,{capture:true,passive:true});
 releaseTop=stop;
}
const USER_SCROLL=['wheel','touchstart','keydown','pointerdown'];
// WebKit scrolls to the URL fragment when the page finishes loading. Each
// route is also a section id, so a hash pushed during startup made Safari jump
// past the page heading. Until the load completes, the hash waits.
let pendingHash=null;
function setRouteHash(route){
 if(document.readyState!=='complete'){
  if(pendingHash===null)addEventListener('load',()=>{const r=pendingHash;pendingHash=null;if(r&&location.hash!=='#'+r)history.pushState(null,'','#'+r);},{once:true});
  pendingHash=route;return;
 }
 if(location.hash!=='#'+route)history.pushState(null,'','#'+route);
}

const LABELS = Object.freeze({
 customer:'Cliente',bartender:'Barista',
 warehouse_manager:'Magazziniere',school_admin:'Admin scuola',
 platform_admin:'Super Admin'
});
// [route, label, icon, short label for the phone tab bar]
const SCREENS = Object.freeze({
 customer:[
  ['menu','Menu','UtensilsCrossed'],['orders','I miei ordini','ClipboardList','Ordini'],
  ['groups','Gruppi','UsersRound'],
  ['workflow-center','Richieste e modifiche','ShieldCheck','Richieste'],
  ['support-center','Assistenza','MessageSquareText'],
  ['accesso','Profilo','UserRound']
 ],
 bartender:[
  ['staff-orders-section','Banco','ClipboardList'],
  ['workflow-center','Richieste','ShieldCheck'],
  ['bar-operations','Servizio e orari','CalendarDays','Servizio'],
  ['cash-workspace','Cassa e turni','Receipt','Cassa'],
  ['offline-terminal','Terminale offline','CloudOff','Offline'],
  ['support-center','Assistenza','MessageSquareText'],
  ['accesso','Profilo','UserRound']
 ],
 warehouse_manager:[
  ['warehouse-inventory','Scorte giornaliere','Boxes','Scorte'],
  ['support-center','Assistenza','MessageSquareText'],
  ['accesso','Profilo','UserRound']
 ],
 school_admin:[
   ['admin-overview','Panoramica','LayoutDashboard','Oggi'],
   ['staff-orders-section','Ordini','ClipboardList'],
   ['workflow-center','Richieste','ShieldCheck'],
   ['support-center','Assistenza','MessageSquareText'],
   ['admin-catalog','Catalogo','ShoppingBag'],
   ['warehouse-inventory','Magazzino','Boxes'],
   ['bar-operations','Orari e servizio','CalendarDays','Orari'],
   ['admin-order-setup','Impostazioni bar','SlidersHorizontal','Impostazioni'],
   ['cash-workspace','Cassa','Receipt'],
   ['school-reports','Report','LayoutDashboard'],
   ['offline-review','Revisione offline','CloudOff','Offline'],
   ['accesso','Profilo e sicurezza','UserRound','Profilo']
  ],
 platform_admin:[
  ['platform-overview','Panoramica','LayoutDashboard'],
  ['platform-schools','Scuole','Building2'],
  ['platform-configuration','Configurazione','SlidersHorizontal','Configura'],
  ['workflow-center','Nuova scuola','Plus'],
  ['accesso','Profilo e sicurezza','UserRound','Profilo']
 ]
});
// What stays in the phone tab bar; everything else lives behind «Altro».
const MOBILE_PRIMARY=Object.freeze({
 customer:['menu','orders','groups','accesso'],
 bartender:['staff-orders-section','cash-workspace','bar-operations'],
 warehouse_manager:['warehouse-inventory','accesso'],
 school_admin:['admin-overview','staff-orders-section','admin-catalog'],
 platform_admin:['platform-overview','platform-schools','platform-configuration']
});
const NAV_GROUPS=Object.freeze({
 platform_admin:{
  'platform-overview':'PANORAMICA',
  'platform-schools':'RETE SCOLASTICA','platform-configuration':'RETE SCOLASTICA',
  'workflow-center':'RETE SCOLASTICA','accesso':'ACCOUNT'
 },
 customer:{
  'menu':'IL TUO INTERVALLO','orders':'IL TUO INTERVALLO','groups':'IL TUO INTERVALLO',
  'workflow-center':'AIUTO','support-center':'AIUTO','accesso':'ACCOUNT'
 },
 warehouse_manager:{
  'warehouse-inventory':'INVENTARIO','support-center':'ACCOUNT','accesso':'ACCOUNT'
 },
 school_admin:{
  'admin-overview':'OGGI','staff-orders-section':'OGGI','workflow-center':'OGGI',
  'support-center':'OGGI','admin-catalog':'OFFERTA','warehouse-inventory':'OFFERTA',
  'bar-operations':'OFFERTA','admin-order-setup':'OFFERTA','cash-workspace':'FINANZE',
  'school-reports':'FINANZE','offline-review':'FINANZE','accesso':'ACCOUNT'
 },
 bartender:{
  'staff-orders-section':'BANCO','workflow-center':'BANCO',
  'bar-operations':'BANCO','cash-workspace':'OPERAZIONI',
  'offline-terminal':'OPERAZIONI','support-center':'OPERAZIONI',
  'accesso':'ACCOUNT'
 }
});
const groupTitle=name=>name.charAt(0)+name.slice(1).toLocaleLowerCase('it-IT');
// One short sentence under the page title: what the page is for, not a slogan.
const PAGE_NOTES=Object.freeze({
 'platform-overview':'Scuole collegate, bar attivi e configurazioni da completare.',
 'platform-schools':'Scuole, bar e stato del servizio.',
 'platform-configuration':'Catalogo, personale, orari, scorte e pagamenti di un bar.',
 'admin-overview':'Ordini e servizio di oggi.',
 'workflow-center':'Approvazioni, modifiche e rimborsi da seguire.',
 'menu':'',
 'orders':'Prenotazioni, pagamenti e QR per il ritiro.',
 'groups':'Un ordine unico per la classe, con quote separate.',
 'staff-orders-section':'',
 'warehouse-inventory':'Disponibilità per giorno e per bar.',
 'admin-catalog':'Categorie, prodotti, prezzi, ingredienti e allergeni.',
 'admin-order-setup':'Posizione della scuola, regole, fasce e scorte.',
 'bar-operations':'Pausa, orari settimanali e chiusure.',
 'cash-workspace':'Apertura, movimenti e chiusura del turno.',
 'school-reports':'Riepiloghi per periodo ed esportazioni.',
 'offline-terminal':'Vendite e ritiri quando manca la rete.',
 'offline-review':'Operazioni registrate senza rete da verificare.',
 'support-center':'Richieste, risposte e segnalazioni.',
 'accesso':'Account, scuole e sicurezza.'
});
const DOM={
 nav:()=>document.getElementById('app-desktop-nav'),
 mobile:()=>document.getElementById('app-mobile-nav'),
 sidebar:()=>document.getElementById('workspace-sidebar'),
 select:()=>document.getElementById('workspace-context-select'),
 pageHead:()=>document.getElementById('workspace-page-head')
};
function create(tag,cls,text=''){
 const el=document.createElement(tag);el.className=cls;el.textContent=text;return el;
}
export function allowedRoute(role,section){
 return Boolean(SCREENS[role]?.some(([route])=>route===section) ||
    (role!=='platform_admin' && section==='support-center'));
}
export function contextsFromMemberships(memberships,schools,aal2,platform=false){
 // A global Super Admin is exclusively a platform operator. School memberships,
 // including legacy customer assignments, must never create a customer UI context.
 // Check the platform role server-side, even before MFA; AAL2 controls its access.
 if(platform)return [{
   key:'platform:platform_admin',
   schoolId:null,
   schoolName:'Tutte le scuole',
   role:'platform_admin',
   verified:aal2
 }];
 const result=[];
 const knownSchools=new Map(schools.map(s=>[s.id,s]));
 const staffSchools=new Set();
 for(const m of memberships){
   if(!knownSchools.has(m.school_id))continue;
   for(const r of m.role_assignments||[]){
     if(!['bartender','warehouse_manager','school_admin'].includes(r.role_code))continue;
     staffSchools.add(m.school_id);
     const key=m.school_id+':'+r.role_code;
     if(result.some(x=>x.key===key))continue;
     result.push({key,schoolId:m.school_id,schoolName:knownSchools.get(m.school_id).name,
       role:r.role_code,verified:r.role_code!=='school_admin'||aal2});
   }
 }
 // A school staff member must not silently fall back to a customer workspace.
 // In particular, AAL1 school admins stay admins with only the MFA page visible.
 for(const school of schools){
   if(staffSchools.has(school.id))continue;
   result.push({key:school.id+':customer',schoolId:school.id,
     schoolName:school.name,role:'customer',verified:true});
 }
 return result;
}
export function chooseInitialContext(contexts,stored) {
 if(!contexts.length)return null;
 // Staff contexts take precedence over stale customer preferences because the
 // application has a single active school/role and no role switcher.
 const staff=['school_admin','bartender','warehouse_manager','platform_admin']
  .map(role=>contexts.find(c=>c.role===role)).find(Boolean);
 if(staff)return staff;
 const preference=contexts.find(c=>c.key===stored);
 if(preference)return preference;
 return ['school_admin','bartender','warehouse_manager','platform_admin','customer']
  .map(role=>contexts.find(c=>c.role===role&&c.verified))
  .find(Boolean)||contexts[0];
}
export function initializeWorkspace(client){
 if(!client)return;
 const sidebar=DOM.sidebar(),nav=DOM.nav(),mobile=DOM.mobile(),select=DOM.select(),
  heading=DOM.pageHead(),root=document.querySelector('#main-content');
 const userId=document.getElementById('workspace-identity');
 const title=document.getElementById('workspace-page-title');
 const subtitle=document.getElementById('workspace-page-subtitle');
 const roleLabel=document.getElementById('workspace-page-role');
 const schoolLabel=document.getElementById('workspace-school-label');
 const pageSection=document.getElementById('workspace-page-section');
 const profileSelect=document.getElementById('workspace-profile-context-select');
 const profileSwitcher=document.getElementById('workspace-profile-switcher');
 const contextBox=sidebar?.querySelector('.workspace-context');
 const routeSections=[...root.children].filter(x=>x.tagName==='SECTION'&&x.id);
 const breadcrumb=document.getElementById('workspace-breadcrumb');
 const contextName=document.getElementById('workspace-context-name');
 const accountLink=document.getElementById('workspace-account');
 const identityAvatar=document.getElementById('workspace-avatar');
 const topAvatar=document.getElementById('workspace-account-avatar');
 const notificationsToggle=document.getElementById('notifications-toggle');
 if(notificationsToggle){notificationsToggle.firstChild?.remove();notificationsToggle.prepend(icon('Bell'));}
 document.getElementById('workspace-signout').prepend(icon('LogOut'));
 const scrim=document.getElementById('workspace-scrim');
 const drawerClose=document.getElementById('workspace-drawer-close');
 const desktop=matchMedia('(min-width: 1024px)');
 let drawerReturn=null;
 function drawerOpen(){return document.body.dataset.drawer==='open';}
 function openDrawer(){
  if(desktop.matches||sidebar.hidden)return;
  drawerReturn=document.activeElement;
  document.body.dataset.drawer='open';scrim.hidden=false;
  mobile.querySelector('.workspace-more-button')?.setAttribute('aria-expanded','true');
  sidebar.setAttribute('role','dialog');sidebar.setAttribute('aria-modal','true');
  requestAnimationFrame(()=>(sidebar.querySelector('[aria-current="page"]')||drawerClose)?.focus());
 }
 function closeDrawer({restore=true}={}){
  if(!drawerOpen())return;
  delete document.body.dataset.drawer;scrim.hidden=true;
  sidebar.removeAttribute('role');sidebar.removeAttribute('aria-modal');
  mobile.querySelector('.workspace-more-button')?.setAttribute('aria-expanded','false');
  if(restore&&drawerReturn?.isConnected)drawerReturn.focus();
  drawerReturn=null;
 }
 drawerClose.addEventListener('click',()=>closeDrawer());
 scrim.addEventListener('click',()=>closeDrawer());
 desktop.addEventListener('change',()=>closeDrawer({restore:false}));
 sidebar.addEventListener('keydown',event=>{
  if(!drawerOpen())return;
  if(event.key==='Escape'){event.preventDefault();closeDrawer();return;}
  if(event.key!=='Tab')return;
  const focusable=[...sidebar.querySelectorAll('a[href],button:not([disabled]),select:not([disabled])')].filter(x=>x.offsetParent!==null);
  const first=focusable[0],last=focusable.at(-1);
  if(event.shiftKey&&document.activeElement===first){event.preventDefault();last?.focus();}
  else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first?.focus();}
 });
 let user=null,contexts=[],active=null,route='',epoch=0,ready=false;
 const storageKey='breakapp:last-workspace-context';
 const offlineRoleCacheKey='breakapp:offline-bartender-context-v1';
 const safelyStored=()=>{try{return localStorage.getItem(storageKey);}catch{return null;}};
 const remember=key=>{try{localStorage.setItem(storageKey,key);}catch{/* nessun errore funzionale */}};
 const clearStore=()=>{try{localStorage.removeItem(storageKey);}catch{}};
 function saveVerifiedOfflineRole(ctx){
  if(!navigator.onLine||ctx.role!=='bartender'||!ctx.verified||!user?.id)return;
  try{localStorage.setItem(offlineRoleCacheKey,JSON.stringify({
   userId:user.id,schoolId:ctx.schoolId,schoolName:ctx.schoolName,
   expiresAt:Date.now()+8*60*60*1000
  }));}catch{/* Storage denied: offline restore may be unavailable. */}
 }
 function restoreOfflineBarista(sessionUser){
  if(navigator.onLine||!sessionUser)return false;
  let cached;
  try{cached=JSON.parse(localStorage.getItem(offlineRoleCacheKey)||'null');}
  catch{return false;}
  if(cached?.userId!==sessionUser.id||
   !/^[0-9a-f-]{36}$/i.test(cached.schoolId||'')||
   typeof cached.schoolName!=='string'||cached.schoolName.length>150||
   !Number.isSafeInteger(cached.expiresAt)||cached.expiresAt<Date.now())
   return false;
  contexts=[{key:cached.schoolId+':bartender',
   schoolId:cached.schoolId,schoolName:cached.schoolName,
   role:'bartender',verified:true}];
  renderContexts();
  sidebar.hidden=false;nav.hidden=false;mobile.hidden=false;heading.hidden=false;
  profileSwitcher.hidden=true;select.disabled=true;profileSelect.disabled=true;
  document.body.dataset.workspace='true';ready=true;
  if(breadcrumb)breadcrumb.hidden=false;
  if(accountLink)accountLink.hidden=false;
  setContext(contexts[0],{restoreRoute:true});
  document.getElementById('school-access-status').textContent=
   'Ruolo Barista ripristinato dalla cache per operazioni locali: il server rivaliderà ogni evento.';
  return true;
 }
 function notifyContext(){
   if(active)window.dispatchEvent(new CustomEvent('breakapp:workspace-context',{
     detail:{schoolId:active.schoolId,role:active.role,barId:null,
        verified:Boolean(active.verified)}
   }));
 }
 function updateSectionVisibility() {
   routeSections.forEach(s=>s.classList.toggle('is-route-active',s.id===route));
 }
 function fallback(){
   const available=SCREENS[active?.role]||[];
   if(!active?.verified)return 'accesso';
   return available[0]?.[0]||'accesso';
 }
 function renderLinks(){
   nav.replaceChildren();mobile.replaceChildren();
   const available=active?.verified?SCREENS[active?.role]||[]:[['accesso','Profilo e sicurezza','UserRound','Profilo']];
   function linkOf(screen,compact=false){
     const [id,label,iconName,short]=screen;
     const a=create('a',compact?'workspace-link mobile-link':'workspace-link');
     a.href='#'+id;a.dataset.route=id;
     const pictogram=create('span','workspace-link-icon');pictogram.append(icon(iconName));
     a.append(pictogram,create('span','workspace-link-label',compact?short||label:label));
     if(compact&&short&&short!==label)a.setAttribute('aria-label',label);
     if(id===route)a.setAttribute('aria-current','page');
     return a;
   }
   // Sidebar (desktop) and drawer (phone): every section, grouped by purpose.
   const groups=NAV_GROUPS[active?.role]||{};
   let current=null;
   for(const screen of available){
     const name=active?.verified?groups[screen[0]]||'ALTRO':'ACCOUNT';
     if(!current||current.dataset.group!==name){
       current=create('div','nav-group');current.dataset.group=name;
       const heading=create('p','nav-group-label',groupTitle(name));
       heading.id='nav-group-'+name.toLowerCase().replace(/[^a-z]+/g,'-');
       current.setAttribute('role','group');current.setAttribute('aria-labelledby',heading.id);
       current.append(heading);nav.append(current);
     }
     current.append(linkOf(screen));
   }
   // Phone tab bar: the few daily sections, then «Altro» opens the drawer.
   const preferred=MOBILE_PRIMARY[active?.role]||[];
   const primary=active?.verified?available.filter(([id])=>preferred.includes(id)):available;
   primary.forEach(screen=>mobile.append(linkOf(screen,true)));
   const rest=available.filter(screen=>!primary.includes(screen));
   if(rest.length){
     const more=create('button','workspace-link workspace-more-button');
     more.type='button';more.setAttribute('aria-controls','workspace-sidebar');
     more.setAttribute('aria-expanded',String(drawerOpen()));
     more.setAttribute('aria-haspopup','dialog');
     const moreIcon=create('span','workspace-link-icon');moreIcon.append(icon('More'));
     more.append(moreIcon,create('span','workspace-link-label','Altro'));
     more.addEventListener('click',()=>drawerOpen()?closeDrawer():openDrawer());
     if(rest.some(([id])=>id===route))more.setAttribute('aria-current','page');
     mobile.append(more);
   }
 }
 function switchRoute(next,{history=true}={}){
   if(!active)return;
   const moveFocus=Boolean(document.activeElement?.closest('#app-desktop-nav,#app-mobile-nav,.app-main section'));
   closeDrawer({restore:false});
   const requested=next||fallback();
   const target=allowedRoute(active.role,requested) && active.verified?requested:
     requested==='accesso'?'accesso':fallback();
   // If a privileged section is still hidden by its controller, never override
   // the controller's [hidden] flag or manufacture access by DOM mutation.
   route=target;
   if(target!=='accesso'&&document.getElementById(target)?.hidden){
     if(!active.verified)route='accesso';
   }
   // Presentation-only route marker for responsive page layouts. Permission
   // checks continue to use the verified context and allowedRoute above.
   document.body.dataset.activeRoute=route;
   if(history)setRouteHash(route);
   updateSectionVisibility();
   renderLinks();
   const name=SCREENS[active.role]?.find(([id])=>id===route)?.[1]||
     (route==='support-center'?'Assistenza':'Profilo');
   title.textContent=name;
   subtitle.textContent=active.verified?
     active.role==='platform_admin'&&route==='workflow-center'?'Il primo passo per un nuovo bar scolastico.':
     PAGE_NOTES[route]??active.schoolName:
     'Completa la verifica a due fattori per accedere alle funzioni riservate.';
   pageSection.textContent=active.role==='platform_admin'?'Piattaforma':active.schoolName;
   roleLabel.textContent=LABELS[active.role];
   if(breadcrumb)breadcrumb.textContent=(active.role==='platform_admin'?LABELS[active.role]:active.schoolName+' · '+LABELS[active.role]);
   document.title=name+' · BreakApp';
   if(moveFocus)title.focus({preventScroll:true});
   const resetScroll=()=>{
     root.scrollTop=0;
     window.scrollTo({top:0,behavior:'instant'});
   };
   resetScroll();
   // Let fragment navigation and the newly displayed section finish their layout.
   // Otherwise the browser can scroll past the page heading during initial Auth.
   requestAnimationFrame(()=>{if(route===target)resetScroll();});
   holdTop(()=>route===target,resetScroll);
   window.dispatchEvent(new CustomEvent('breakapp:route-changed',{
     detail:{route,schoolId:active.schoolId,role:active.role}
   }));
 }
 function setContext(context,{restoreRoute=false}={}){
   active=context;
   const brandHome=document.querySelector('.site-header .brand');
   if(brandHome)brandHome.href='#'+fallback();
   remember(context.key);
   saveVerifiedOfflineRole(context);
   select.value=context.key;
   profileSelect.value=context.key;
   schoolLabel.textContent=context.schoolName;
   if(contextName)contextName.textContent=LABELS[context.role];
   document.getElementById('workspace-identity-role').textContent=LABELS[context.role];
   document.body.dataset.activeRole=context.role;
   document.body.dataset.activeSchool=context.schoolId||'global';
   notifyContext();
   if(context.schoolId){
     for(const id of context.role==='customer'
       ?['menu-school']:context.role==='school_admin'
       ?['catalog-school','ops-school']:[]) {
       const target=document.getElementById(id);
       if(target&&[...target.options].some(option=>option.value===context.schoolId)
          &&target.value!==context.schoolId){
         target.value=context.schoolId;
         target.dispatchEvent(new Event('change',{bubbles:true}));
       }
     }
   }
   switchRoute(restoreRoute?location.hash.slice(1):null,{history:true});
   // Guard against entering staff views with a context not verified at AAL2.
 }
 function renderContexts(){
   select.replaceChildren();profileSelect.replaceChildren();
   for(const item of contexts){
     const text=LABELS[item.role]+' · '+item.schoolName+
       (!item.verified?' · Verifica 2FA':'');
     select.add(new Option(text,item.key));
     profileSelect.add(new Option(text,item.key));
   }
 }
 function signOutUI(){
   epoch++;ready=false;user=null;contexts=[];active=null;route='';
   const brandHome=document.querySelector('.site-header .brand');
   if(brandHome)brandHome.href='#accesso';
   document.body.dataset.workspace='false';
   document.body.removeAttribute('data-active-role');
   document.body.removeAttribute('data-active-school');
   document.body.removeAttribute('data-active-route');
   sidebar.hidden=true;nav.hidden=true;mobile.hidden=true;heading.hidden=true;
   if(breadcrumb)breadcrumb.hidden=true;
   if(accountLink)accountLink.hidden=true;
   profileSwitcher.hidden=true;
   closeDrawer({restore:false});
   routeSections.forEach(s=>s.classList.remove('is-route-active'));
 }
 async function refreshSession(userNext){
   if(!userNext){signOutUI();return;}
   const token=++epoch;
   user=userNext;
   userId.textContent=userNext.email||'Account BreakApp';
   const initials=(userNext.email||'B').split('@')[0].split(/[.\s_-]+/).filter(Boolean).slice(0,2).map(x=>x[0]).join('').toUpperCase();
   if(identityAvatar)identityAvatar.textContent=initials;
   if(topAvatar)topAvatar.textContent=initials;
   if(restoreOfflineBarista(userNext))return;
   const [access,sch,assurance,platform]=await Promise.allSettled([
     loadSchoolAccess(client,userNext.id),
     client.from('schools').select('id,name').eq('is_active',true).order('name'),
     client.auth.mfa.getAuthenticatorAssuranceLevel(),
     client.rpc('has_current_platform_admin_role')
   ]);
   if(token!==epoch||user?.id!==userNext.id)return;
   if(access.status!=='fulfilled'||sch.status!=='fulfilled'||
      assurance.status!=='fulfilled'||platform.status!=='fulfilled'||
      sch.value.error||assurance.value.error||platform.value.error) {
     // On request error: fail closed. Do not render stale roles from local state.
     active=null;nav.replaceChildren();mobile.replaceChildren();
     routeSections.forEach(s=>s.classList.remove('is-route-active'));
     sidebar.hidden=true;heading.hidden=true;
     if(breadcrumb)breadcrumb.hidden=true;
     if(accountLink)accountLink.hidden=true;
     document.body.dataset.workspace='false';
     document.body.removeAttribute('data-active-route');
     document.getElementById('school-access-status').textContent=
       'Impossibile verificare ruolo e scuola. Riprova dal Profilo.';
     return;
   }
   const schools=sch.value.data||[];
   const memberships=access.value.memberships||[];
   const aal2=assurance.value.data.currentLevel==='aal2';
   const isPlatform=platform.status==='fulfilled'&&!platform.value.error&&platform.value.data===true;
   contexts=contextsFromMemberships(memberships,schools,aal2,isPlatform);
   if(!contexts.length)contexts=[{key:'unassigned:customer',role:'customer',
     schoolId:null,schoolName:'Nessuna scuola disponibile',verified:true}];
   renderContexts();
   const selected=chooseInitialContext(contexts,active?.key||safelyStored());
   sidebar.hidden=false;nav.hidden=false;mobile.hidden=false;heading.hidden=false;
   // Every account belongs to one school with one role (a Super Admin works
   // from the platform screens, which pick the school themselves). No
   // school/role switcher is shown anywhere: the header says where you are.
   const canSwitch=false;
   profileSwitcher.hidden=!canSwitch;
   select.disabled=!canSwitch;
   select.hidden=!canSwitch;
   if(contextBox)contextBox.hidden=!canSwitch;
   if(contextName)contextName.hidden=canSwitch;
   profileSelect.disabled=!canSwitch;
   if(breadcrumb)breadcrumb.hidden=false;
   if(accountLink)accountLink.hidden=false;
   document.body.dataset.workspace='true';ready=true;
   setContext(selected,{restoreRoute:true});
 }
 select.addEventListener('change',()=>{
   const next=contexts.find(x=>x.key===select.value);
   if(next)setContext(next);
 });
 profileSelect.addEventListener('change',()=>{
   const next=contexts.find(x=>x.key===profileSelect.value);
   if(next)setContext(next);
 });
 document.getElementById('workspace-signout').addEventListener('click',()=>{
   document.getElementById('logout-button').click();
 });
 const routeFromLocation=()=>{
   if(!ready)return;
   const next=decodeURIComponent(location.hash.slice(1));
   if(next!==route)switchRoute(next,{history:false});
 };
 window.addEventListener('hashchange',routeFromLocation);
 window.addEventListener('popstate',routeFromLocation);
 window.addEventListener('breakapp:access-updated',()=>{
   if(user)void refreshSession(user);
 });
 window.addEventListener('breakapp:mfa-verified',()=>{
   if(user)void refreshSession(user);
 });
 window.addEventListener('breakapp:platform-onboarded',()=>{
   if(active?.role==='platform_admin'&&active.verified)switchRoute('platform-configuration');
 });
 window.addEventListener('click',event=>{
   const link=event.target.closest('a[href^="#"]');
   if(ready&&link&&!event.defaultPrevented&&event.button===0&&!event.metaKey&&!event.ctrlKey&&!event.shiftKey&&!event.altKey){
     const destination=link.getAttribute('href').slice(1);
     if(!destination||routeSections.some(section=>section.id===destination)){
       event.preventDefault();switchRoute(destination||fallback());
     }
   }
 });
 const onAuth=(_event,session)=>queueMicrotask(()=>{
   const next=session?.user||null;
   if(!next)signOutUI();
   else if(user?.id!==next.id)void refreshSession(next);
 });
 client.auth.onAuthStateChange(onAuth);
 client.auth.getUser().then(async({data,error})=>{
   if(!error&&data?.user && user?.id!==data.user.id)void refreshSession(data.user);
   else if(error&&!navigator.onLine){
    const {data:cached}=await client.auth.getSession();
    if(cached?.session?.user && user?.id!==cached.session.user.id)
     void refreshSession(cached.session.user);
   }
 });
 window.addEventListener('online',()=>{
  if(user)void refreshSession(user);
 });
 return {refresh:()=>{if(user)void refreshSession(user);},getContext:()=>active};
}
