import {icon} from '../../core/icons.js';
const make=(tag,text='',cls='')=>{const el=document.createElement(tag);el.className=cls;el.textContent=text;return el;};
const $=id=>document.getElementById(id);
export function initializePlatformDashboard(client,metric){
 const overview=$('platform-overview'),directory=$('platform-schools'),configuration=$('platform-configuration'),
  metrics=$('platform-metrics'),preview=$('platform-school-list'),network=$('platform-network'),
  listing=$('platform-directory-list'),feedback=$('platform-feedback'),directoryFeedback=$('platform-directory-feedback'),
  search=$('platform-school-search'),filter=$('platform-school-filter'),refresh=$('platform-refresh'),
  dialog=$('platform-school-state-dialog'),reason=$('platform-school-state-reason'),stateSubmit=$('platform-school-state-submit');
 let context=null,user=null,schools=[],bars=[],epoch=0,loadedAt=0,busy=false,selectedSchool=null,pendingState=null;
 const authorized=()=>Boolean(user&&context?.role==='platform_admin'&&context.verified);
 $('platform-date').textContent=new Intl.DateTimeFormat('it-IT',{timeZone:'Europe/Rome',weekday:'long',day:'numeric',month:'long',year:'numeric'}).format(new Date());
 function empty(parent,title,note,action=false){
  const box=make('div','','empty-state');box.append(icon('Building2'),make('strong',title),make('p',note));
  if(action){const link=make('a','Aggiungi la prima scuola','button button-primary button-small');link.href='#workflow-center';box.append(link);}parent.replaceChildren(box);
 }
 function manageLink(s){
  const link=make('a','Gestisci','school-manage');link.href='#platform-configuration';link.setAttribute('aria-label','Gestisci '+s.name);link.append(icon('ChevronRight'));
  link.addEventListener('click',()=>window.dispatchEvent(new CustomEvent('breakapp:platform-open-school',{detail:{schoolId:s.id}})));return link;
 }
 function table(rows,full=false){
  const result=make('table','','school-table'),caption=make('caption',full?'Scuole della piattaforma':'Una selezione delle tue scuole','sr-only'),head=make('thead'),header=make('tr'),body=make('tbody');
  for(const[label,cls]of [['Scuola',''],['Bar','school-bars-column'],['Stato',''],['Azioni','']]){const th=make('th',label,cls);th.scope='col';header.append(th);}head.append(header);
  for(const s of rows){
   const row=make('tr'),schoolCell=make('td'),identity=make('div','','school-name'),info=make('div'),names=bars.filter(b=>b.school_id===s.id),activeBars=names.filter(b=>b.is_active),
    initials=s.name.trim().split(/\s+/).slice(0,2).map(word=>word[0]).join('').toUpperCase();
   info.append(make('strong',s.name),make('small',names.length?names.length+(names.length===1?' bar collegato':' bar collegati'):'Nessun bar collegato'));
   identity.append(make('span',initials,'school-monogram'),info);schoolCell.append(identity);
   const barCell=make('td',activeBars.length+'/'+names.length+' attivi','school-bars-column');barCell.title=names.map(b=>b.name).join(', ');
   const stateCell=make('td');stateCell.append(make('span',s.is_active?'Attiva':'Sospesa','status-badge'+(s.is_active?'':' is-paused')));
   const actionCell=make('td'),actions=make('div','','school-row-actions');
   if(s.is_active)actions.append(manageLink(s));
   if(full){
    const toggle=make('button',s.is_active?'Sospendi':'Riattiva','school-state-button');toggle.type='button';toggle.setAttribute('aria-label',(s.is_active?'Sospendi ':'Riattiva ')+s.name);
    toggle.addEventListener('click',()=>openStateDialog(s));actions.append(toggle);
   }
   actionCell.append(actions);row.append(schoolCell,barCell,stateCell,actionCell);body.append(row);
  }
  result.append(caption,head,body);return result;
 }
 function renderDirectory(){
  if(!authorized())return;
  const query=search.value.trim().toLocaleLowerCase('it'),state=filter.value;
  const rows=schools.filter(s=>(state==='all'||(state==='active'?s.is_active:!s.is_active))&&(!query||s.name.toLocaleLowerCase('it').includes(query)||bars.some(b=>b.school_id===s.id&&b.name.toLocaleLowerCase('it').includes(query))));
  $('platform-directory-count').textContent=rows.length+' '+(rows.length===1?'scuola':'scuole')+(rows.length!==schools.length?' su '+schools.length:'');
  if(rows.length)listing.replaceChildren(table(rows,true));
  else empty(listing,schools.length?'Nessun risultato':'La tua rete inizia qui',schools.length?'Prova con un altro nome o cambia il filtro.':'Aggiungi una scuola per configurare il suo bar.',!schools.length);
 }
 function render(){
  const active=schools.filter(s=>s.is_active),paused=schools.length-active.length,activeIds=new Set(active.map(s=>s.id)),activeBars=bars.filter(b=>b.is_active&&activeIds.has(b.school_id));
  metrics.replaceChildren(metric('Scuole collegate',schools.length,'Nella tua piattaforma','Building2'),metric('Scuole attive',active.length,'Con accesso abilitato','Check'),metric('Bar attivi',activeBars.length,'Nelle scuole attive','UtensilsCrossed'),metric('Scuole sospese',paused,'Con accesso sospeso','Pause'));
  $('platform-school-count').textContent=String(schools.length);
  if(schools.length)preview.replaceChildren(table(schools.slice(0,5)));
  else empty(preview,'Benvenuto nella tua piattaforma','Crea la prima scuola e inizia a organizzare il servizio.',true);
  const summary=make('div','','network-summary'),ring=make('div','','network-ring'),svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
  svg.setAttribute('viewBox','0 0 136 136');svg.setAttribute('aria-hidden','true');
  const proportion=schools.length?active.length/schools.length:0,circumference=2*Math.PI*55;
  for(const cls of ['ring-track','ring-value']){const c=document.createElementNS(svg.namespaceURI,'circle');for(const[k,v]of Object.entries({cx:'68',cy:'68',r:'55',class:cls}))c.setAttribute(k,v);if(cls==='ring-value')c.setAttribute('stroke-dasharray',(circumference*proportion)+' '+circumference);svg.append(c);}
  const label=make('div','','network-ring-label');label.append(make('strong',schools.length?Math.round(100*proportion)+'%':'—'),make('span','scuole attive'));ring.append(svg,label);
  const legend=make('div','','network-legend');for(const[text,value]of [['Scuole attive',active.length],['Scuole sospese',paused],['Bar collegati',bars.length]]){const row=make('div');row.append(make('span',text),make('strong',String(value)));legend.append(row);}summary.append(ring,legend);network.replaceChildren(summary);renderDirectory();
 }
 async function readAll(name,columns){
  const all=[];
  for(let start=0;start<50000;start+=1000){
   const result=await client.from(name).select(columns).order('name').order('id').range(start,start+999);
   if(result.error)throw result.error;all.push(...(result.data||[]));if((result.data||[]).length<1000)return all;
  }
  throw new Error('Directory troppo estesa. Contatta l’assistenza per caricare tutte le scuole.');
 }
 async function load(){
  if(!authorized()||busy)return;
  const token=++epoch;busy=true;refresh.disabled=true;metrics.setAttribute('aria-busy','true');
  if(!loadedAt){metrics.replaceChildren(...Array.from({length:4},()=>make('div','','dashboard-skeleton')));}
  feedback.textContent='Aggiornamento della piattaforma…';directoryFeedback.textContent='';
  try{
   const auth=await client.rpc('is_current_platform_admin');
   if(token!==epoch||!authorized())return;
   if(auth.error||auth.data!==true)throw new Error('Verifica i tuoi permessi e la verifica in due passaggi dal Profilo.');
   const [s,b]=await Promise.all([readAll('schools','id,name,is_active'),readAll('bars','id,name,school_id,is_active')]);
   if(token!==epoch||!authorized())return;schools=s;bars=b;render();loadedAt=Date.now();
   feedback.dataset.type='information';feedback.textContent='Ultimo aggiornamento alle '+new Date().toLocaleTimeString('it-IT',{timeZone:'Europe/Rome',hour:'2-digit',minute:'2-digit'});
  }catch(error){
   if(token!==epoch)return;schools=[];bars=[];loadedAt=0;metrics.replaceChildren();network.replaceChildren();
   empty(preview,'Non riusciamo a caricare i dati','Usa Aggiorna per riprovare.');empty(listing,'Directory non disponibile','Riprova tra poco o verifica l’accesso dal Profilo.');$('platform-directory-count').textContent='';$('platform-school-count').textContent='';
   feedback.dataset.type='error';feedback.textContent='Caricamento non riuscito. '+error.message;directoryFeedback.textContent=feedback.textContent;
  }finally{if(token===epoch){busy=false;refresh.disabled=false;metrics.setAttribute('aria-busy','false');}}
 }
 function openStateDialog(s){
  if(!authorized())return;selectedSchool=s;reason.value='';$('platform-school-state-feedback').textContent='';
  $('platform-school-state-title').textContent=(s.is_active?'Sospendi':'Riattiva')+' la scuola';
  $('platform-school-state-description').textContent=s.name+'. '+(s.is_active?'L’accesso della scuola e le prenotazioni verranno sospesi.':'La scuola tornerà attiva. La disponibilità del bar dipenderà dalla sua configurazione.');
  stateSubmit.textContent=s.is_active?'Sospendi scuola':'Riattiva scuola';dialog.showModal();
 }
 const closeDialog=()=>{if(!pendingState){dialog.close();selectedSchool=null;}};
 $('platform-school-state-close').addEventListener('click',closeDialog);$('platform-school-state-cancel').addEventListener('click',closeDialog);
 dialog.addEventListener('cancel',event=>{if(pendingState)event.preventDefault();});
 $('platform-school-state-form').addEventListener('submit',async event=>{
  event.preventDefault();if(!authorized()||!selectedSchool||pendingState||!event.currentTarget.reportValidity())return;
  const s=selectedSchool,token=epoch,actor=user.id,operation={};pendingState=operation;stateSubmit.disabled=true;
  try{
   const result=await client.rpc('platform_set_school_active',{p_school:s.id,p_active:!s.is_active,p_reason:reason.value.trim()});if(result.error)throw result.error;
   if(token!==epoch||!authorized()||user.id!==actor)return;
   dialog.close();selectedSchool=null;await load();window.dispatchEvent(new CustomEvent('breakapp:platform-school-updated'));
  }catch(error){if(authorized()&&user.id===actor)$('platform-school-state-feedback').textContent='Modifica non riuscita: '+error.message;}
  finally{if(pendingState===operation)pendingState=null;stateSubmit.disabled=false;}
 });
 function reset(){epoch++;busy=false;loadedAt=0;schools=[];bars=[];selectedSchool=null;dialog.close();metrics.replaceChildren();preview.replaceChildren();listing.replaceChildren();network.replaceChildren();feedback.textContent='';directoryFeedback.textContent='';search.value='';filter.value='all';refresh.disabled=false;metrics.setAttribute('aria-busy','false');}
 function enter(){const ok=authorized();overview.hidden=!ok;directory.hidden=!ok;configuration.hidden=!ok;if(ok)void load();}
 search.addEventListener('input',renderDirectory);filter.addEventListener('change',renderDirectory);refresh.addEventListener('click',()=>void load());
 window.addEventListener('breakapp:workspace-context',event=>{reset();context=event.detail;enter();});
 window.addEventListener('breakapp:route-changed',event=>{if(['platform-overview','platform-schools'].includes(event.detail.route)&&authorized()&&Date.now()-loadedAt>60000)void load();});
 window.addEventListener('breakapp:platform-onboarded',()=>{loadedAt=0;void load();});
 client.auth.onAuthStateChange((_event,session)=>queueMicrotask(()=>{const next=session?.user||null;if(next?.id!==user?.id){reset();context=null;}user=next;if(!user)context=null;enter();}));
 client.auth.getUser().then(({data,error})=>{if(!error){user=data?.user||null;enter();}});
}
