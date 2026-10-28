import { loadSchoolAccess } from '../auth/access.js';
import {icon} from '../../core/icons.js';

const LABELS = Object.freeze({
 customer:'Cliente',bartender:'Barista',
 warehouse_manager:'Magazziniere',school_admin:'Admin scuola',
 platform_admin:'Super Admin'
});
const SCREENS = Object.freeze({
 customer:[
  ['menu','Menu','UtensilsCrossed'],['orders','I miei ordini','ClipboardList'],
  ['groups','Gruppi','UsersRound'],['accesso','Profilo','UserRound']
  ,['workflow-center','Richieste e modifiche','ClipboardList']
 ],
 bartender:[
  ['staff-orders-section','Ordini da preparare','ClipboardList'],
  ['workflow-center','Approvazioni ed eccezioni','ClipboardList'],
  ['bar-operations','Servizio e orari','CalendarDays'],
  ['cash-workspace','Cassa e turni','ClipboardList'],
  ['offline-terminal','Operazioni offline','Boxes'],
  ['support-center','Assistenza','MessageSquareText'],
  ['accesso','Profilo','UserRound']
 ],
 warehouse_manager:[
  ['warehouse-inventory','Scorte giornaliere','Boxes'],
  ['accesso','Profilo','UserRound']
 ],
 school_admin:[
  ['admin-overview','Panoramica','LayoutDashboard'],
  ['school-reports','Report e annunci','LayoutDashboard'],
  ['staff-orders-section','Gestione ordini','ClipboardList'],
  ['workflow-center','Approvazioni ed eccezioni','ClipboardList'],
  ['admin-catalog','Catalogo','ShoppingBag'],
  ['warehouse-inventory','Magazzino','Boxes'],
  ['cash-workspace','Cassa e chiusure','ClipboardList'],
  ['offline-review','Revisione offline','ClipboardList'],
  ['admin-order-setup','Impostazioni bar','SlidersHorizontal'],
  ['bar-operations','Calendario','CalendarDays'],
  ['support-center','Centro ticket','MessageSquareText'],
  ['accesso','Profilo e sicurezza','UserRound']
 ],
 platform_admin:[
  ['platform-overview','Panoramica','LayoutDashboard'],
  ['platform-schools','Scuole','Building2'],
  ['platform-configuration','Configurazione','SlidersHorizontal'],
  ['workflow-center','Nuova scuola','Plus'],
  ['accesso','Profilo e sicurezza','UserRound']
 ]
});
const PAGE_NOTES=Object.freeze({
 'platform-overview':'Uno sguardo alla rete delle tue scuole.',
 'platform-schools':'Tutte le scuole, i bar e il loro stato, in un unico posto.',
 'platform-configuration':'Scegli una scuola e organizza il suo servizio.',
 'admin-overview':'Ordini, catalogo e servizio: la giornata a colpo d’occhio.',
 'workflow-center':'Gestisci le richieste che richiedono la tua attenzione.'
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
 for(const school of schools){
   result.push({key:school.id+':customer',schoolId:school.id,
     schoolName:school.name,role:'customer',verified:true});
 }
 for(const m of memberships){
   if(!knownSchools.has(m.school_id))continue;
   for(const r of m.role_assignments||[]){
     if(!['bartender','warehouse_manager','school_admin'].includes(r.role_code))continue;
     const key=m.school_id+':'+r.role_code;
     if(result.some(x=>x.key===key))continue;
     result.push({key,schoolId:m.school_id,schoolName:knownSchools.get(m.school_id).name,
       role:r.role_code,verified:r.role_code!=='school_admin'||aal2});
   }
 }
 return result;
}
export function chooseInitialContext(contexts,stored) {
 if(!contexts.length)return null;
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
 const routeSections=[...root.children].filter(x=>x.tagName==='SECTION'&&x.id);
 const breadcrumb=document.getElementById('workspace-breadcrumb');
 const contextName=document.getElementById('workspace-context-name');
 const accountLink=document.getElementById('workspace-account');
 const identityAvatar=document.getElementById('workspace-avatar');
 const topAvatar=document.getElementById('workspace-account-avatar');
 const notificationsToggle=document.getElementById('notifications-toggle');
 if(notificationsToggle){notificationsToggle.firstChild?.remove();notificationsToggle.prepend(icon('Bell'));}
 document.getElementById('workspace-signout').prepend(icon('LogOut'));
 const moreContainer=create('div','workspace-more');
 moreContainer.hidden=true;
 moreContainer.id='workspace-more-items';
 moreContainer.setAttribute('aria-label','Altre sezioni');
 document.body.append(moreContainer);
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
   nav.replaceChildren();mobile.replaceChildren();moreContainer.replaceChildren();
   const available=active?.verified?SCREENS[active?.role]||[]:[['accesso','Profilo e sicurezza','UserRound']];
   function linkOf(screen,compact=false){
     const [id,label,iconName]=screen;
     const a=create('a',compact?'workspace-link mobile-link':'workspace-link');
     a.href='#'+id;a.dataset.route=id;
     const pictogram=create('span','workspace-link-icon');pictogram.append(icon(iconName));
     a.append(pictogram,
       create(compact?'small':'span','workspace-link-label',label));
     if(id===route)a.setAttribute('aria-current','page');
     return a;
   }
   for(const screen of available){
     if(screen[0]==='accesso')nav.append(create('span','workspace-nav-caption','Account'));
     nav.append(linkOf(screen));
   }
   const compact=available.length>4?[...available.slice(0,3)]:available;
   compact.forEach(screen=>mobile.append(linkOf(screen,true)));
   if(available.length>4){
     const more=create('button','workspace-link workspace-more-button');
     more.type='button';more.setAttribute('aria-controls','workspace-more-items');
     more.setAttribute('aria-expanded','false');
     const moreIcon=create('span','workspace-link-icon');moreIcon.append(icon('More'));
     more.append(moreIcon,
       create('small','workspace-link-label','Altro'));
     more.addEventListener('click',()=>{
       moreContainer.hidden=!moreContainer.hidden;
       more.setAttribute('aria-expanded',String(!moreContainer.hidden));
     });
     mobile.append(more);
     for(const screen of available.slice(3))moreContainer.append(linkOf(screen));
     if(available.slice(3).some(([id])=>id===route))more.setAttribute('aria-current','page');
   }
 }
 function switchRoute(next,{history=true}={}){
   if(!active)return;
   const moveFocus=Boolean(document.activeElement?.closest('#app-desktop-nav,#app-mobile-nav,#workspace-more-items,.app-main section'));
   const requested=next||fallback();
   const target=allowedRoute(active.role,requested) && active.verified?requested:
     requested==='accesso'?'accesso':fallback();
   // If a privileged section is still hidden by its controller, never override
   // the controller's [hidden] flag or manufacture access by DOM mutation.
   route=target;
   if(target!=='accesso'&&document.getElementById(target)?.hidden){
     if(!active.verified)route='accesso';
   }
   if(history && location.hash!=='#'+route)window.history.pushState(null,'','#'+route);
   updateSectionVisibility();
   renderLinks();
   moreContainer.hidden=true;
   const name=route==='support-center'?'Centro assistenza':
     SCREENS[active.role]?.find(([id])=>id===route)?.[1]||'Profilo';
   title.textContent=name;
   subtitle.textContent=active.verified?
     active.role==='platform_admin'&&route==='workflow-center'?'Il primo passo per un nuovo bar scolastico.':
     PAGE_NOTES[route]||active.schoolName:
     'Completa la verifica a due fattori per accedere alle funzioni riservate.';
   pageSection.textContent=active.role==='platform_admin'?'Gestione piattaforma':active.schoolName;
   roleLabel.textContent=LABELS[active.role];
   if(breadcrumb)breadcrumb.textContent=LABELS[active.role]+' / '+name;
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
   window.dispatchEvent(new CustomEvent('breakapp:route-changed',{
     detail:{route,schoolId:active.schoolId,role:active.role}
   }));
 }
 function setContext(context,{restoreRoute=false}={}){
   active=context;
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
   document.body.dataset.workspace='false';
   document.body.removeAttribute('data-active-role');
   document.body.removeAttribute('data-active-school');
   sidebar.hidden=true;nav.hidden=true;mobile.hidden=true;heading.hidden=true;
   if(breadcrumb)breadcrumb.hidden=true;
   if(accountLink)accountLink.hidden=true;
   profileSwitcher.hidden=true;
   moreContainer.hidden=true;
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
   const previous=active?.key;
   const selected=contexts.find(x=>x.key===previous)||chooseInitialContext(contexts,safelyStored());
   sidebar.hidden=false;nav.hidden=false;mobile.hidden=false;heading.hidden=false;
   // A sole Super Admin context must not offer a meaningless role switcher.
   profileSwitcher.hidden=contexts.length<2;
   select.disabled=contexts.length<2;
   select.hidden=contexts.length<2;
   if(contextName)contextName.hidden=contexts.length>1;
   profileSelect.disabled=contexts.length<2;
   if(breadcrumb)breadcrumb.hidden=false;
   if(accountLink)accountLink.hidden=false;
   document.body.dataset.workspace='true';ready=true;
   setContext(selected,{restoreRoute:!!previous});
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
   if(!moreContainer.hidden && !moreContainer.contains(event.target) &&
      !mobile.contains(event.target)){
     moreContainer.hidden=true;
     mobile.querySelector('.workspace-more-button')?.setAttribute('aria-expanded','false');
   }
 });
 window.addEventListener('keydown',event=>{
   if(event.key==='Escape'&&!moreContainer.hidden){
     moreContainer.hidden=true;
     const more=mobile.querySelector('.workspace-more-button');more?.setAttribute('aria-expanded','false');more?.focus();
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
