import {formatEuro} from '../catalog/utils.js';
const make=(tag,text='',cls='')=>{const n=document.createElement(tag);n.textContent=text;n.className=cls;return n;};
const button=(text,run)=>{const b=make('button',text,'button button-outline button-small');b.type='button';b.addEventListener('click',()=>void run(b));return b;};
export function initializeOrderWorkflows(client){
 if(!client)return;
 const section=make('section','','container workflow-center');section.id='workflow-center';section.hidden=true;
 section.append(make('h2','Richieste e gestione ordini'));
 const status=make('p');status.setAttribute('role','status');status.setAttribute('aria-live','polite');
 const controls=make('div','','order-actions'),barSelect=make('select'),presence=make('input');presence.type='checkbox';
 barSelect.setAttribute('aria-label','Bar di servizio');
 const label=make('label','');label.append(presence,document.createTextNode(' Sono in servizio e disponibile per le approvazioni'));
 controls.append(barSelect,label,button('Aggiorna',()=>reload()));
 const capacity=make('form'),limit=make('input');limit.type='number';limit.min='1';limit.max='30';limit.value='3';limit.setAttribute('aria-label','Numero massimo di richieste attive');
 capacity.append(make('label','Richieste attive contemporaneamente'),limit,make('button','Salva limite','button button-outline button-small'));
 const list=make('div','','service-list');section.append(controls,capacity,status,list);document.getElementById('main-content').append(section);
 let context=null,user=null,epoch=0,activeBar=null;
 const say=(s,error=false)=>{status.textContent=s;status.dataset.type=error?'error':'information';};
 async function rpc(name,args){const r=await client.rpc(name,args);if(r.error)throw r.error;return r.data;}
 async function act(b,fn){b.disabled=true;try{await fn();await reload();say('Operazione registrata sul server.');}
  catch(e){say(e.message,true);}finally{b.disabled=false;}}
 async function slots(bar){const r=await client.from('pickup_windows').select('id,service_date,starts_at').eq('bar_id',bar).eq('is_active',true).order('service_date').order('starts_at').limit(200);if(r.error)throw r.error;return r.data||[];}
 async function reload(){
  if(!user||!context)return;
  const v=++epoch,staff=['bartender','school_admin'].includes(context.role);
  controls.hidden=!staff;presence.closest('label').hidden=context.role!=='bartender';capacity.hidden=context.role!=='school_admin';
  try{
   const rows=await rpc('list_order_approvals',{p_school:staff?context.schoolId:null});if(v!==epoch)return;
   list.replaceChildren(make('h3','Grandi ordini'));
   if(!rows.length)list.append(make('p','Nessuna richiesta di approvazione.'));
   for(const a of rows){
    const box=make('article','','order-card');box.append(make('h4',(a.group_order_id?'Gruppo':'Ordine')+' · '+a.state),
     make('p',a.service_date+' '+a.starts_at.slice(0,5)),make('p',a.reason||'La richiesta non è confermata finché il personale non la approva.'));
    if(a.lease_until&&a.state==='active')box.append(make('p','Scade alle '+new Date(a.lease_until).toLocaleTimeString('it-IT')));
    if(staff&&a.state==='active'){
     box.append(button('Approva',b=>act(b,()=>rpc('decide_order_approval',{p_request:a.id,p_approve:true,p_reason:''}))),
      button('Rifiuta',b=>act(b,async()=>{const reason=prompt('Motivazione facoltativa del rifiuto');if(reason===null)return;
       await rpc('decide_order_approval',{p_request:a.id,p_approve:false,p_reason:reason});})));
    }
    if(a.owner_id===user.id&&['queued','active','awaiting_reschedule'].includes(a.state)){
     box.append(button('Annulla richiesta',b=>act(b,async()=>{if(confirm('Annullare la richiesta ed avviare gli eventuali rimborsi?'))await rpc('respond_approval_schedule',{p_request:a.id,p_window:null,p_cancel:true});})));
     if(a.state==='awaiting_reschedule'){
      box.append(make('p','Scegli entro '+new Date(a.response_until).toLocaleString('it-IT')));
      const select=make('select');select.setAttribute('aria-label','Nuova fascia della richiesta');
      for(const w of await slots(a.bar_id))select.add(new Option(w.service_date+' '+w.starts_at.slice(0,5),w.id));
      box.append(select,button('Conferma nuova fascia',b=>act(b,()=>rpc('respond_approval_schedule',{p_request:a.id,p_window:select.value,p_cancel:false}))));
     }
    }
    list.append(box);
   }
   window.dispatchEvent(new CustomEvent('breakapp:workflow-loaded',{detail:{section,context,user,client,rpc,act,make,button,formatEuro}}));
  }catch(e){if(v===epoch)say(e.message,true);}
 }
 async function heartbeat(){
  if(!presence.checked||context?.role!=='bartender'||!activeBar||!navigator.onLine)return;
  try{await rpc('set_staff_service_presence',{p_bar:activeBar,p_present:true});}catch(e){say(e.message,true);presence.checked=false;}
 }
 presence.addEventListener('change',()=>void act(presence,async()=>{activeBar=barSelect.value;await rpc('set_staff_service_presence',{p_bar:activeBar,p_present:presence.checked});}));
 capacity.addEventListener('submit',e=>{e.preventDefault();void act(capacity.querySelector('button'),()=>rpc('set_approval_capacity',{p_school:context.schoolId,p_limit:Number(limit.value)}));});
 barSelect.addEventListener('change',async()=>{if(activeBar&&presence.checked)await rpc('set_staff_service_presence',{p_bar:activeBar,p_present:false}).catch(e=>say(e.message,true));activeBar=barSelect.value;presence.checked=false;});
 window.addEventListener('breakapp:workspace-context',async e=>{
  if(activeBar&&presence.checked&&navigator.onLine)void rpc('set_staff_service_presence',{p_bar:activeBar,p_present:false}).catch(()=>{});
  presence.checked=false;context=e.detail;epoch++;
  if(['bartender','school_admin'].includes(context?.role)){
   const r=await client.from('bars').select('id,name').eq('school_id',context.schoolId).eq('is_active',true);
   if(!r.error){barSelect.replaceChildren();for(const b of r.data||[])barSelect.add(new Option(b.name,b.id));activeBar=barSelect.value;}
  }
  void reload();
 });
 client.auth.onAuthStateChange((_e,s)=>queueMicrotask(()=>{user=s?.user||null;if(!user){epoch++;list.replaceChildren();presence.checked=false;}else void reload();}));
 client.auth.getUser().then(({data})=>{user=data?.user||null;void reload();});
 setInterval(()=>{void heartbeat();if(!section.hidden&&document.visibilityState==='visible'&&!section.contains(document.activeElement))void reload();},45000);
 return {section,reload,rpc,act,make,button,get context(){return context;},get user(){return user;}};
}
