import {parseEuroToCents} from '../catalog/utils.js';
const $=id=>document.getElementById(id);
const el=(tag,text='',cls='')=>{const n=document.createElement(tag);n.textContent=text;n.className=cls;return n;};
const money=cents=>new Intl.NumberFormat('it-IT',{style:'currency',currency:'EUR'}).format(Number(cents)/100);
export function initializeCashWorkspace(client,terminal){
 if(!client)return;
 let ctx=null,actor=null,snapshot=null,bars=[],epoch=0,busy=false;
 const panel=$('cash-workspace'),bar=$('cash-bar'),feedback=$('cash-feedback');
 const say=(message,error=false)=>{feedback.textContent=message;feedback.dataset.type=error?'error':'information';};
 const current=()=>(snapshot?.sessions||[]).find(s=>s.bar_id===bar.value&&s.actor_id===actor&&!s.closed_at);
 async function persist(){if(snapshot)await terminal?.cacheSnapshot({...snapshot,bars});}
 function render(){
  const session=current(),admin=ctx?.role==='school_admin';
  $('cash-open-form').hidden=admin||Boolean(session);
  $('cash-movement-form').hidden=admin||!session;
  $('cash-close-form').hidden=admin||!session;
  $('cash-adjust-form').hidden=!admin;
  $('cash-current').textContent=session
   ?'Turno aperto · Fondo '+money(session.opening_cents)+' · Cassa attesa '+money(session.current_expected_cents)
   :admin?'Verifica le chiusure e inserisci eventuali rettifiche motivate.':'Nessun tuo turno aperto per questo bar.';
  $('cash-unassigned').textContent=Number(snapshot?.unassigned_cents)
   ?'Incassi senza turno associato: '+money(snapshot.unassigned_cents)+'. Verifica il registro prima del conteggio.':'';
  const history=$('cash-history'),select=$('cash-adjust-session');history.replaceChildren();select.replaceChildren();
  for(const s of snapshot?.sessions||[]){
   const row=el('article','','pilot-card');
   row.append(el('strong','Turno '+s.id.slice(0,8)+' · '+(s.closed_at?'Chiuso':'Aperto')),
    el('p','Aperto il '+new Date(s.opened_at).toLocaleString('it-IT')+' · Fondo '+money(s.opening_cents)));
   if(s.closed_at){
    row.append(el('p','Atteso '+money(s.expected_cents)+' · Contato '+money(s.counted_cents)+
     ' · Differenza '+money(Number(s.counted_cents)-Number(s.expected_cents))),el('p',s.closing_reason));
    if(Number(s.adjustments_cents))row.append(el('p','Rettifiche successive: '+money(s.adjustments_cents)+'. Chiusura originale conservata.'));
    select.add(new Option(s.id.slice(0,8)+' · '+new Date(s.closed_at).toLocaleString('it-IT'),s.id));
   }
   history.append(row);
  }
  if(!history.children.length)history.append(el('p','Non sono presenti turni di cassa.'));
  const entries=$('cash-entries');entries.replaceChildren();
  const names={receipt:'Incasso',deposit:'Versamento',withdrawal:'Prelievo',adjustment:'Rettifica Admin'};
  for(const item of (snapshot?.entries||[]).slice(0,100))entries.append(el('p',
   new Date(item.created_at).toLocaleString('it-IT')+' · '+(names[item.kind]||item.kind)+' '+
   money(item.amount_cents)+(item.reason?' · '+item.reason:'')));
 }
 async function refresh(){
  if(!ctx?.schoolId)return;
  const token=++epoch,school=ctx.schoolId;
  if(!navigator.onLine||await terminal?.hasPending()){
   const cached=terminal?.getSnapshot();
   if(cached?.school_id===school){snapshot=structuredClone(cached);bars=cached.bars||bars;}
   render();say('Dati locali cifrati. Invia prima le operazioni dalla sezione Offline.');return;
  }
  const {data,error}=await client.rpc('cash_workspace',{p_school:school});
  if(token!==epoch||ctx?.schoolId!==school)return;
  if(error){say(error.message,true);return;}
  snapshot={...data,school_id:school};await persist();render();say('Registro aggiornato dal server.');
 }
 async function operate(form,action,amount,reason,sessionId){
  if(busy||!ctx?.verified||!bar.value)return;
  const key=form.dataset.requestKey||crypto.randomUUID();form.dataset.requestKey=key;
  busy=true;form.querySelector('button[type=submit]').disabled=true;
  try{
   if(navigator.onLine&&!await terminal?.hasPending()){
    const {error}=await client.rpc('record_cash_operation',{p_bar:bar.value,p_session:sessionId,
     p_action:action,p_amount:amount,p_reason:reason,p_key:key});
    if(error)throw error;await refresh();
   }else{
    if(ctx.role!=='bartender'||!terminal?.isUnlocked())throw Error('Sblocca prima il dispositivo Offline con il PIN.');
    const row=current();
    if(action==='open'&&row)throw Error('Hai già un turno aperto.');
    if(action!=='open'&&(!row||row.id!==sessionId))throw Error('Turno locale non disponibile.');
    if(action==='close'&&amount!==Number(row.current_expected_cents)&&reason.length<10)
     throw Error('La differenza di cassa richiede una motivazione di almeno dieci caratteri.');
    await terminal.queueShift({bar_id:bar.value,session_id:sessionId,action,amount_cents:amount,reason,request_key:key});
    snapshot||={school_id:ctx.schoolId,sessions:[],entries:[],unassigned_cents:0};
    if(action==='open')snapshot.sessions.unshift({id:sessionId,bar_id:bar.value,actor_id:actor,
     opening_cents:amount,current_expected_cents:amount,opened_at:new Date().toISOString(),closed_at:null});
    else if(action==='close')Object.assign(row,{closed_at:new Date().toISOString(),expected_cents:row.current_expected_cents,
     counted_cents:amount,closing_reason:reason});
    else row.current_expected_cents=Number(row.current_expected_cents)+(action==='withdrawal'?-amount:amount);
    await persist();render();say('Operazione salvata nella coda cifrata; sincronizza appena possibile.');
   }
   form.reset();delete form.dataset.requestKey;delete form.dataset.sessionId;
  }catch(error){say(error.message||'Operazione non registrata.',true);}
  finally{busy=false;form.querySelector('button[type=submit]').disabled=false;}
 }
 for(const [id,action,amountId,reasonId] of [
  ['cash-open-form','open','cash-opening',null],['cash-movement-form',null,'cash-amount','cash-reason'],
  ['cash-close-form','close','cash-counted','cash-close-reason'],['cash-adjust-form','adjustment','cash-adjust-amount','cash-adjust-reason']]){
  const form=$(id);
  form.addEventListener('input',()=>{delete form.dataset.requestKey;});
  form.addEventListener('submit',event=>{
   event.preventDefault();if(!form.reportValidity())return;
   try{
    const selected=action||$('cash-action').value,raw=$(amountId).value.trim();
    const amount=(selected==='adjustment'&&raw.startsWith('-')?-1:1)*parseEuroToCents(selected==='adjustment'?raw.replace(/^-/,''):raw);
    if(selected==='adjustment'&&!navigator.onLine)throw Error('Rettifiche Admin disponibili solo online con 2FA.');
    if(selected==='close'&&!confirm('Confermi il conteggio fisico di '+money(amount)+'? La chiusura sarà immutabile.'))return;
    if(selected==='open')form.dataset.sessionId||=crypto.randomUUID();
    const sessionId=selected==='open'?form.dataset.sessionId:selected==='adjustment'?$('cash-adjust-session').value:current()?.id;
    void operate(form,selected,amount,reasonId?$(reasonId).value.trim():'',sessionId);
   }catch(e){say(e.message,true);}
  });
 }
 bar.addEventListener('change',render);$('cash-refresh').addEventListener('click',()=>void refresh());
 window.addEventListener('breakapp:cash-refresh',()=>void refresh());
 window.addEventListener('breakapp:offline-vault-state',()=>{
  if(!terminal?.isUnlocked())return;
  const cached=terminal.getSnapshot();
  if(cached?.school_id===ctx?.schoolId){snapshot=structuredClone(cached);bars=cached.bars||bars;
   if(!bar.options.length)for(const b of bars)bar.add(new Option(b.name,b.id));render();}
  else void persist();
 });
 window.addEventListener('breakapp:cash-recorded',event=>{
  const row=snapshot?.sessions?.find(s=>s.id===event.detail.sessionId);
  if(row){row.current_expected_cents=Number(row.current_expected_cents)+event.detail.amount;
   void persist().then(render).catch(()=>say('Verifica la coda cifrata prima di chiudere la cassa.',true));}
 });
 window.addEventListener('breakapp:workspace-context',async event=>{
  epoch++;ctx=event.detail;snapshot=null;bars=[];actor=null;bar.replaceChildren();render();
  panel.hidden=!ctx?.verified||!['school_admin','bartender'].includes(ctx.role);
  if(panel.hidden)return;
  const token=epoch,school=ctx.schoolId;
  const {data:session}=await client.auth.getSession();actor=session?.session?.user?.id;
  if(!navigator.onLine){render();return;}
  const {data,error}=await client.from('bars').select('id,name').eq('school_id',school).eq('is_active',true).order('name');
  if(token!==epoch)return;if(error){say(error.message,true);return;}
  bars=data||[];for(const b of bars)bar.add(new Option(b.name,b.id));await refresh();
 });
 client.auth.onAuthStateChange((_e,session)=>{if(!session){epoch++;ctx=null;actor=null;snapshot=null;panel.hidden=true;
  $('cash-history').replaceChildren();$('cash-entries').replaceChildren();}});
}
