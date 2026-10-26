import { WEEKDAY_LABELS,parseWeeklyPeriods,formatWeeklyPeriods } from './calendar-core.js';

const byId=id=>document.getElementById(id);
const make=(tag,text,cls='')=>{const node=document.createElement(tag);node.textContent=text;node.className=cls;return node;};

export function initializeBarService(client) {
  if(!client)return;
  const panel=byId('bar-operations'),barSelect=byId('service-bar');
  const feedback=byId('service-feedback'),summary=byId('service-state-summary');
  const hoursPanel=byId('service-weekly-panel');
  const weekday=byId('service-weekday'),periodInput=byId('service-weekly-periods');
  const hoursList=byId('service-weekly-list');
  const closuresList=byId('service-closures-list'),eventsList=byId('service-events-list');
  const previewButton=byId('service-closure-preview'),closeButton=byId('service-closure-confirm');
  const impact=byId('service-closure-impact');
  const pauseButton=byId('service-pause-button'),resumeButton=byId('service-resume-button');
  let context=[],serviceState=null,hours=[],closures=[],isAdmin=false,previewKey='';
  let generation=0,lastUser=null;

  const report=(message,error=false)=>{feedback.textContent=message;feedback.dataset.type=error?'error':'information';};
  const currentBar=()=>context.find(x=>x.id===barSelect.value);
  function invalidatePreview(){previewKey='';closeButton.disabled=true;impact.replaceChildren();}
  function closureParams() {
    return {
      p_bar_id:barSelect.value,p_date:byId('service-closure-date').value,
      p_start:byId('service-closure-start').value,
      p_end:byId('service-closure-end').value,
      p_kind:byId('service-closure-kind').value,
      p_reason:byId('service-closure-reason').value.trim()
    };
  }
  function renderWeekly() {
    hoursList.replaceChildren();
    const grouped=Array.from({length:7},(_,d)=>hours.filter(h=>h.weekday===d));
    for(let day=1;day<=7;day++){
      const idx=day%7,entry=make('div','','service-list-item');
      entry.append(make('strong',WEEKDAY_LABELS[idx]),
        make('span',formatWeeklyPeriods(grouped[idx])));
      hoursList.append(entry);
    }
    periodInput.value=hours.filter(x=>x.weekday===Number(weekday.value))
      .map(x=>x.starts_at.slice(0,5)+'-'+x.ends_at.slice(0,5)).join('\n');
  }
  function renderClosures() {
    closuresList.replaceChildren();
    if(!closures.length)closuresList.append(make('p','Nessuna chiusura registrata.'));
    for(const c of closures){
      const item=make('div','','service-list-item');
      item.append(make('strong',c.service_date+' · '+c.starts_at.slice(0,5)+'–'+c.ends_at.slice(0,5)),
        make('span',(c.closure_type==='extraordinary'?'Straordinaria':'Programmata')+
          ' · '+(c.reopened_at?'Riaperto':'Chiuso')),
        make('span',c.reason));
      if(!c.reopened_at){
        const button=make('button','Riapri intervallo','button button-outline button-small');
        button.type='button';
        button.addEventListener('click',async()=>{
          if(!confirm('Riaprire questo intervallo? Gli ordini annullati NON saranno ripristinati.'))return;
          button.disabled=true;
          report('Riapertura in corso…');
          const {error}=await client.rpc('reopen_bar_interval',{p_closure_id:c.id});
          if(error){report(error.message,true);button.disabled=false;return;}
          invalidatePreview();await reload();
          window.dispatchEvent(new CustomEvent('breakapp:service-changed',{detail:{barId:barSelect.value}}));
        });
        item.append(button);
      }
      closuresList.append(item);
    }
  }
  function renderEvents(events) {
    eventsList.replaceChildren();
    if(!events.length)eventsList.append(make('p','Nessuna operazione registrata.'));
    const labels={
      booking_paused:'Pausa prenotazioni',booking_resumed:'Prenotazioni riprese',
      weekly_hours_updated:'Orari modificati',closure_created:'Chiusura registrata',
      closure_reopened:'Riapertura registrata'
    };
    for(const e of events){
      const d=make('div','','service-list-item');
      d.append(make('strong',labels[e.action]||e.action));
      d.append(make('span',new Date(e.created_at).toLocaleString('it-IT')));
      eventsList.append(d);
    }
  }
  function renderState() {
    const paused=serviceState&&!serviceState.accepting_orders;
    summary.replaceChildren(
      make('strong',paused?'Nuove prenotazioni sospese':'Nuove prenotazioni attive'),
      make('span',paused?'Motivo: '+(serviceState.reason||'Non indicato'):
        'Gli ordini già confermati rimangono disponibili al personale.')
    );
    summary.dataset.paused=String(Boolean(paused));
    pauseButton.disabled=Boolean(paused);
    resumeButton.disabled=!paused;
    hoursPanel.hidden=!isAdmin;
    byId('service-closure-kind').querySelector('option[value="planned"]').disabled=!isAdmin;
    if(!isAdmin&&byId('service-closure-kind').value==='planned')
      byId('service-closure-kind').value='extraordinary';
  }
  async function reload(){
    const bar=currentBar();if(!bar)return;
    const token=++generation;
    report('Aggiornamento orari e chiusure…');
    const [stateRes,hoursRes,closuresRes,eventsRes]=await Promise.all([
      client.from('bar_service_state').select('accepting_orders,reason,updated_at')
        .eq('bar_id',bar.id).maybeSingle(),
      client.from('bar_opening_hours').select('weekday,starts_at,ends_at')
        .eq('bar_id',bar.id).order('weekday').order('starts_at'),
      client.from('bar_closures').select('id,service_date,starts_at,ends_at,closure_type,reason,reopened_at')
        .eq('bar_id',bar.id).order('service_date',{ascending:false}).limit(60),
      client.from('bar_service_events').select('action,created_at')
        .eq('bar_id',bar.id).order('created_at',{ascending:false}).limit(15)
    ]);
    if(token!==generation)return;
    const error=stateRes.error||hoursRes.error||closuresRes.error||eventsRes.error;
    if(error){report('Impossibile caricare lo stato reale: '+error.message,true);return;}
    serviceState=stateRes.data;hours=hoursRes.data||[];closures=closuresRes.data||[];
    renderState();renderWeekly();renderClosures();renderEvents(eventsRes.data||[]);
    report('Dati aggiornati da Supabase.');
  }
  function populate() {
    const old=barSelect.value;
    barSelect.replaceChildren();
    for(const b of context)barSelect.add(new Option(b.name,b.id));
    if(context.some(b=>b.id===old))barSelect.value=old;
    activateBar();
  }
  function activateBar() {
    const b=currentBar();
    isAdmin=Boolean(b?.admin);
    invalidatePreview();
    if(b){panel.hidden=false;void reload();}
    else panel.hidden=true;
  }
  async function readAccess(user){
    const token=++generation;
    if(!user){hide();return;}
    const [m,a]=await Promise.all([
      client.from('school_memberships')
        .select('school_id,role_assignments(role_code)')
        .eq('user_id',user.id).eq('membership_status','active'),
      client.auth.mfa.getAuthenticatorAssuranceLevel()
    ]);
    if(token!==generation)return;
    if(m.error||a.error){hide();return;}
    const aal2=a.data.currentLevel==='aal2',tenantRights=new Map();
    for(const member of m.data||[]) {
      const roles=(member.role_assignments||[]).map(x=>x.role_code);
      const admin=roles.includes('school_admin')&&aal2;
      const operator=roles.includes('bartender')||admin;
      if(operator)tenantRights.set(member.school_id,admin);
    }
    if(!tenantRights.size){hide();return;}
    const bars=await client.from('bars').select('id,school_id,name,is_active')
      .in('school_id',[...tenantRights.keys()]).eq('is_active',true).order('name');
    if(token!==generation)return;
    if(bars.error){hide();return;}
    context=(bars.data||[]).filter(x=>tenantRights.has(x.school_id))
      .map(x=>({...x,admin:tenantRights.get(x.school_id)}));
    populate();
  }
  function hide(){
    generation++;context=[];hours=[];closures=[];serviceState=null;isAdmin=false;
    panel.hidden=true;barSelect.replaceChildren();invalidatePreview();
  }
  byId('service-refresh').addEventListener('click',()=>{
    if(lastUser)void readAccess(lastUser);
  });
  barSelect.addEventListener('change',activateBar);
  weekday.addEventListener('change',renderWeekly);
  byId('service-weekly-form').addEventListener('submit',async event=>{
    event.preventDefault();
    const bar=currentBar();if(!bar?.admin)return report('Permessi Admin e 2FA richiesti.',true);
    let periods;
    try{periods=parseWeeklyPeriods(periodInput.value);}
    catch(err){return report(err.message,true);}
    report('Salvataggio orari in corso…');
    const {error}=await client.rpc('set_bar_weekly_hours',{
      p_bar_id:bar.id,p_weekday:Number(weekday.value),p_periods:periods
    });
    if(error)return report(error.message,true);
    await reload();
    window.dispatchEvent(new CustomEvent('breakapp:service-changed',{detail:{barId:bar.id}}));
  });
  byId('service-pause-form').addEventListener('submit',async event=>{
    event.preventDefault();
    const bar=currentBar();if(!bar)return;
    const reason=byId('service-pause-reason').value.trim();
    if(reason.length<3)return report('Inserisci una motivazione di almeno tre caratteri.',true);
    pauseButton.disabled=true;report('Sospensione delle nuove prenotazioni…');
    const {error}=await client.rpc('set_bar_booking_pause',{
      p_bar_id:bar.id,p_paused:true,p_reason:reason
    });
    if(error){pauseButton.disabled=false;return report(error.message,true);}
    await reload();
    window.dispatchEvent(new CustomEvent('breakapp:service-changed',{detail:{barId:bar.id}}));
  });
  resumeButton.addEventListener('click',async()=>{
    const bar=currentBar();if(!bar)return;
    if(!confirm('Riprendere l’accettazione di nuove prenotazioni?'))return;
    resumeButton.disabled=true;
    const {error}=await client.rpc('set_bar_booking_pause',{
      p_bar_id:bar.id,p_paused:false,p_reason:''
    });
    if(error){resumeButton.disabled=false;return report(error.message,true);}
    await reload();
    window.dispatchEvent(new CustomEvent('breakapp:service-changed',{detail:{barId:bar.id}}));
  });
  const closeForm=byId('service-closure-form');
  closeForm.querySelectorAll('input,select,textarea').forEach(node=>
    node.addEventListener('input',invalidatePreview));
  previewButton.addEventListener('click',async()=>{
    const f=closureParams();
    if(!closeForm.reportValidity())return;
    if(!f.p_bar_id||!f.p_date||!f.p_start||!f.p_end||f.p_start>=f.p_end)
      return report('Seleziona un intervallo valido.',true);
    invalidatePreview();report('Analisi degli ordini interessati…');
    const {data,error}=await client.rpc('preview_bar_closure',{
      p_bar_id:f.p_bar_id,p_date:f.p_date,p_start:f.p_start,p_end:f.p_end
    });
    if(error)return report(error.message,true);
    const active=Number(data?.active_orders||0);
    const paid=Number(data?.paid_cents||0);
    impact.replaceChildren(
      make('strong',active+' ordini attivi coinvolti'),
      make('p',paid>0
        ? 'Ci sono importi già incassati. La chiusura sarà bloccata finché il rimborso automatico non sarà disponibile.'
        : 'Nessun importo incassato da rimborsare per gli ordini coinvolti.'),
      make('p',f.p_kind==='planned'&&active>0
        ? 'Una chiusura programmata non può cancellare ordini già attivi.'
        : 'Confermare la chiusura annullerà gli ordini non consegnati e non pagati nell’intervallo. Sarà registrato un avviso in app.')
    );
    if(paid>0||(f.p_kind==='planned'&&active>0)){
      report('L’operazione è bloccata per proteggere ordini e pagamenti.',true);
      return;
    }
    previewKey=JSON.stringify(f);closeButton.disabled=false;
    report('Anteprima verificata. Leggi le conseguenze prima di confermare.');
  });
  closeForm.addEventListener('submit',async event=>{
    event.preventDefault();
    const f=closureParams();
    if(previewKey!==JSON.stringify(f))return report('Ricalcola l’anteprima prima di confermare.',true);
    if(!confirm('Confermi la chiusura? Gli ordini non pagati interessati saranno annullati. Gli ordini già annullati non torneranno attivi alla riapertura.'))return;
    closeButton.disabled=true;report('Creazione chiusura e gestione ordini…');
    const {error}=await client.rpc('close_bar_interval',f);
    if(error){invalidatePreview();return report(error.message,true);}
    invalidatePreview();
    await reload();
    window.dispatchEvent(new CustomEvent('breakapp:service-changed',{detail:{barId:f.p_bar_id}}));
  });
  client.auth.onAuthStateChange((_event,session)=>queueMicrotask(()=>{
    const user=session?.user||null;
    lastUser=user;
    if(!user)hide();
    else void readAccess(user);
  }));
  client.auth.getUser().then(({data,error})=>{
    if(error)return;
    lastUser=data?.user||null;
    void readAccess(lastUser);
  });
}
