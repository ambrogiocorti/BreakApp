const el=(tag,value='',css='')=>{const n=document.createElement(tag);n.className=css;n.textContent=value;return n;};
const byId=id=>document.getElementById(id);
const money=c=>new Intl.NumberFormat('it-IT',{style:'currency',currency:'EUR'}).format(c/100);
const dateRome=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Rome',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
function inviteId(input){
 const value=String(input||'').trim();
 let candidate=value;
 try{const url=new URL(value);candidate=url.searchParams.get('invite')||'';}catch{/* direct token */}
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(candidate))
  throw new Error('Incolla un link di invito valido o il relativo codice UUID.');
 return candidate;
}
function coordinates(){
 return new Promise((resolve,reject)=>{
  if(!('geolocation' in navigator))return reject(new Error('Geolocalizzazione non supportata dal dispositivo.'));
  navigator.geolocation.getCurrentPosition(p=>{
   if(p.coords.accuracy>100)return reject(new Error('Precisione GPS superiore a 100 m: riprova all’aperto.'));
   resolve({p_latitude:p.coords.latitude,p_longitude:p.coords.longitude,
    p_accuracy_m:p.coords.accuracy,p_observed_at:new Date(p.timestamp).toISOString()});
  },e=>reject(new Error(e.code===1?'Autorizza la posizione per entrare nel gruppo.':
    'Posizione non disponibile: '+e.message)),{enableHighAccuracy:true,maximumAge:0,timeout:15000});
 });
}
export function initializeGroupDrafts(client){
 if(!client)return;
 const panel=byId('groups'),list=byId('groups-list'),feedback=byId('groups-feedback'),
  createForm=byId('groups-create-form'),joinForm=byId('groups-join-form'),
  school=byId('groups-school'),bar=byId('groups-bar'),windowSelect=byId('groups-window'),
  detailPanel=byId('group-detail'),productsPanel=byId('group-products'),
  membersPanel=byId('group-members'),cartForm=byId('group-cart-form');
 let user=null,schools=[],bars=[],windows=[],products=[],detail=null,version=0,createdKey=null;
 const report=(message,error=false)=>{
  feedback.textContent=message;feedback.dataset.type=error?'error':'information';
 };
 function options(select,values){
  const old=select.value;select.replaceChildren();
  for(const [id,name] of values)select.add(new Option(name,id));
  if(values.some(x=>x[0]===old))select.value=old;
 }
 async function selectSchool(){
  options(bar,bars.filter(b=>b.school_id===school.value).map(b=>[b.id,b.name]));
  await selectBar();
 }
 async function selectBar(){
  options(windowSelect,windows.filter(w=>w.bar_id===bar.value).map(w=>[w.id,
   w.service_date+' · '+w.starts_at.slice(0,5)+'–'+w.ends_at.slice(0,5)]));
 }
 async function schoolsAndWindows(){
  const [a,b,w]=await Promise.all([
   client.from('schools').select('id,name').eq('is_active',true).order('name'),
   client.from('bars').select('id,school_id,name').eq('is_active',true).order('name'),
   client.from('pickup_windows').select('id,bar_id,service_date,starts_at,ends_at')
    .eq('is_active',true).gte('service_date',dateRome()).order('service_date').limit(150)
  ]);
  if(a.error||b.error||w.error)throw a.error||b.error||w.error;
  schools=a.data||[];bars=b.data||[];windows=w.data||[];
  options(school,schools.map(s=>[s.id,s.name]));
  await selectSchool();
 }
 async function myGroups(){
  const {data,error}=await client.rpc('list_my_group_drafts');
  if(error)throw error;
  list.replaceChildren();
  if(!Array.isArray(data)||!data.length)list.append(el('p','Nessuna bozza gruppo presente.'));
  for(const g of data||[]){
   const card=el('div','','group-draft-row');
   card.append(el('strong',g.title),el('small',
     (g.coordinator?'Coordinatore':'Partecipante')+' · '+g.my_status+
      ' · '+(g.status==='draft'?'Bozza':g.status)));
   const open=el('button','Apri gruppo','button button-outline button-small');
   open.type='button';open.addEventListener('click',()=>void showGroup(g.id));
   card.append(open);list.append(card);
  }
 }
 function renderLines(){
  productsPanel.replaceChildren();
  for(const p of products){
   const row=el('div','','group-product-row');
   const desc=el('div','','group-product-desc');
   desc.append(el('strong',p.name),el('span',money(p.price_cents)));
   const qty=el('input');qty.type='number';qty.min='0';qty.max='1000';qty.step='1';
   qty.value=String(detail.my_items.find(x=>x.product_id===p.id)?.quantity||0);
   qty.dataset.productId=p.id;
   qty.setAttribute('aria-label','Quantità di '+p.name);
   row.append(desc,qty);productsPanel.append(row);
  }
  if(!products.length)productsPanel.append(el('p','Nessun prodotto pubblicato per questo bar.'));
 }
 async function showGroup(id){
  const seq=++version;
  report('Caricamento bozza gruppo…');
  const {data,error}=await client.rpc('group_draft_details',{p_group_id:id});
  if(seq!==version)return;
  if(error){report(error.message,true);return;}
  detail=data;
  detailPanel.hidden=false;
  byId('group-detail-title').textContent=detail.title;
  byId('group-detail-meta').textContent=
   'Stato: '+detail.status+' · '+(detail.coordinator?'Coordinatore':'Partecipante')+
   ' · iscrizione: '+detail.my_status;
  byId('group-aggregate').replaceChildren(
   el('strong','Riepilogo aggregato'),
   el('span',(detail.totals?.count||0)+' prodotti · '+money(Number(detail.totals?.total_cents||0)))
  );
  const invite=byId('group-invite');
  invite.hidden=!detail.coordinator||!detail.invite_token;
  if(!invite.hidden){
   const u=new URL(location.href);
   u.searchParams.set('invite',detail.invite_token);u.hash='groups';
   byId('group-invite-link').value=u.toString();
  }
  const accepted=detail.my_status==='accepted'&&detail.status==='draft';
  byId('group-personal').hidden=!accepted;
  byId('group-coordinator-panel').hidden=!detail.coordinator;
  const readyButton=byId('group-ready');
  readyButton.textContent=detail.my_ready?'Modifica il mio ordine':'Ho finito';
  cartForm.hidden=!accepted||Boolean(detail.my_ready);
  if(accepted){
   const p=await client.from('products')
    .select('id,name,price_cents,category_id,categories!inner(is_active)')
    .eq('school_id',detail.school_id).eq('bar_id',detail.bar_id)
    .eq('is_active',true).eq('categories.is_active',true).order('name');
   if(seq!==version)return;
   if(p.error){report(p.error.message,true);return;}
   products=p.data||[];renderLines();
  }
  membersPanel.replaceChildren();
  if(detail.coordinator && Array.isArray(detail.members)){
   for(const m of detail.members){
    const row=el('div','','group-member-row');
    row.append(el('span',(m.member_id===user.id?'Io':m.member_id.slice(0,8))+
      ' · '+m.status+' · '+(m.ready?'Pronto':'In composizione')+' · '+m.line_count+' prodotti'));
    if(m.status==='pending'){
     for(const [label,approved] of [['Approva',true],['Rifiuta',false]]){
      const btn=el('button',label,'button button-outline button-small');btn.type='button';
      btn.addEventListener('click',async()=>{
       btn.disabled=true;
       const r=await client.rpc('review_group_member',{
        p_group_id:detail.id,p_member_id:m.member_id,p_approve:approved});
       if(r.error){report(r.error.message,true);btn.disabled=false;return;}
       await showGroup(detail.id);await myGroups();
      });
      row.append(btn);
     }
    }
    membersPanel.append(row);
   }
  }
  report(detail.my_status==='pending'
    ?'In attesa dell’approvazione del coordinatore.'
    :'Gruppo caricato. Le bozze non riservano scorte né incassano denaro.');
 }
 async function reload(){
  if(!user)return;
  report('Aggiornamento gruppi…');
  try{await schoolsAndWindows();await myGroups();report('Elenco gruppi aggiornato.');}
  catch(err){report(err.message,true);}
 }
 createForm.addEventListener('submit',async event=>{
  event.preventDefault();if(!user||!createForm.reportValidity())return;
  const button=createForm.querySelector('button[type=submit]');button.disabled=true;
  createdKey ||= crypto.randomUUID();
  const limit=byId('groups-limit').value;
  const {data,error}=await client.rpc('create_group_draft',{
   p_bar_id:bar.value,p_window_id:windowSelect.value,p_request_key:createdKey,
   p_title:byId('groups-create-title').value.trim(),
   p_requires_approval:byId('groups-entry-mode').value==='approval',
   p_max_members:limit?Number(limit):null
  });
  button.disabled=false;
  if(error){report(error.message,true);return;}
  createdKey=null;createForm.reset();
  await myGroups();await showGroup(data);
 });
 joinForm.addEventListener('submit',async event=>{
  event.preventDefault();if(!user||!joinForm.reportValidity())return;
  const button=joinForm.querySelector('button[type=submit]');button.disabled=true;
  try{
   const token=inviteId(byId('groups-invite-token').value);
   report('Richiesta del consenso GPS…');
   const pos=await coordinates();
   const {data,error}=await client.rpc('join_group_draft',{p_invite_token:token,...pos});
   if(error)throw error;
   await myGroups();await showGroup(data);
  }catch(err){report(err.message,true);}
  finally{button.disabled=false;}
 });
 cartForm.addEventListener('submit',async event=>{
  event.preventDefault();if(!detail||!user)return;
  const items=[];
  for(const n of productsPanel.querySelectorAll('input[data-product-id]')){
   const q=Number(n.value);
   if(!Number.isSafeInteger(q)||q<0||q>1000)return report('Quantità non valida.',true);
   if(q>0)items.push({product_id:n.dataset.productId,quantity:q});
  }
  const {error}=await client.rpc('replace_group_personal_cart',{p_group_id:detail.id,p_items:items});
  if(error)return report(error.message,true);
  await showGroup(detail.id);
 });
 byId('group-ready').addEventListener('click',async()=>{
  if(!detail)return;
  const {error}=await client.rpc('set_group_personal_ready',{
    p_group_id:detail.id,p_ready:!detail.my_ready
  });
  if(error)return report(error.message,true);
  await showGroup(detail.id);
 });
 byId('group-invite-copy').addEventListener('click',async()=>{
  try{await navigator.clipboard.writeText(byId('group-invite-link').value);
   report('Link invito copiato.');}
  catch{byId('group-invite-link').select();report('Seleziona e copia il link invito.');}
 });
 byId('groups-refresh').addEventListener('click',()=>void reload());
 school.addEventListener('change',()=>void selectSchool());
 bar.addEventListener('change',()=>void selectBar());
 window.addEventListener('breakapp:route-changed',event=>{
  if(event.detail?.route==='groups'&&user)void reload();
 });
 function session(next){
  const changed=user?.id!==next?.id;user=next;
  panel.hidden=!user;
  if(!user){version++;detail=null;detailPanel.hidden=true;list.replaceChildren();return;}
  if(changed)void reload();
  if(changed&&location.search.includes('invite=')){
   const invite=new URLSearchParams(location.search).get('invite');
   if(invite){byId('groups-invite-token').value=invite;location.hash='groups';}
  }
 }
 client.auth.onAuthStateChange((_event,s)=>queueMicrotask(()=>session(s?.user||null)));
 client.auth.getUser().then(({data,error})=>{if(!error)session(data?.user||null);});
}
