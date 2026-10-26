const byId=id=>document.getElementById(id);
const el=(tag,cls='',value='')=>{const n=document.createElement(tag);n.className=cls;n.textContent=value;return n;};
export function initializeWarehouseInventory(client){
 if(!client)return;
 const panel=byId('warehouse-inventory'),select=byId('warehouse-bar'),
 date=byId('warehouse-date'),feedback=byId('warehouse-feedback'),
 list=byId('warehouse-items');
 let context=null,bars=[],items=[],version=0,user=null;
 const report=(message,error=false)=>{feedback.textContent=message;feedback.dataset.type=error?'error':'information';};
 function today(){
   return new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Rome',year:'numeric',
      month:'2-digit',day:'2-digit'}).format(new Date());
 }
 date.value=today();
 function empty(reason){list.replaceChildren(el('p','warehouse-empty',reason));}
 async function sync(){
   const bar=bars.find(b=>b.id===select.value);
   const day=date.value,token=++version;
   if(!bar||!day){empty('Seleziona il bar e una data.');return;}
   report('Caricamento scorte reali…');
   const [products,stocks]=await Promise.all([
     client.from('products').select('id,name,is_active,price_cents')
      .eq('school_id',bar.school_id).eq('bar_id',bar.id).order('name'),
     client.from('daily_stock').select('id,product_id,capacity,allocated')
      .eq('school_id',bar.school_id).eq('bar_id',bar.id)
      .eq('service_date',day)
   ]);
   if(token!==version)return;
   const error=products.error||stocks.error;
   if(error){empty('Impossibile caricare le scorte.');report(error.message,true);return;}
   const stockMap=new Map((stocks.data||[]).map(s=>[s.product_id,s]));
   items=(products.data||[]).map(p=>({...p,stock:stockMap.get(p.id)||null}));
   render(bar,day);
   report('Scorte aggiornate. Le modifiche sono salvate sul database.');
 }
 function render(bar,day){
   list.replaceChildren();
   if(!items.length){empty('Nessun prodotto disponibile per questo bar. Crea prima il catalogo.');return;}
   for(const p of items){
     const row=el('article','warehouse-row');
     const info=el('div','warehouse-product');
     info.append(el('strong','',p.name),el('span','',
       p.stock?'Prenotati: '+p.stock.allocated:'Scorte del giorno non impostate'));
     const form=el('form','warehouse-row-controls');
     const label=el('label','warehouse-quantity');
     label.textContent='Quantità totale';
     const amount=el('input');amount.type='number';amount.step='1';amount.min=String(p.stock?.allocated||0);
     amount.value=p.stock?.capacity===null||!p.stock?'':String(p.stock.capacity);
     amount.placeholder='Illimitata';amount.setAttribute('aria-label','Capacità di '+p.name);
     const unlimited=el('label','warehouse-unlimited');
     const check=el('input');check.type='checkbox';
     check.checked=p.stock?.capacity===null&&Boolean(p.stock);
     check.setAttribute('aria-label','Disponibilità illimitata per '+p.name);
     unlimited.append(check,el('span','','Illimitata'));
     const button=el('button','button button-primary button-small','Salva');
     button.type='submit';
     const updateQuantity=()=>{
       amount.disabled=check.checked;
       if(check.checked)amount.value='';
     };
     check.addEventListener('change',updateQuantity);
     updateQuantity();
     form.append(label);label.append(amount);form.append(unlimited,button);
     form.addEventListener('submit',async event=>{
       event.preventDefault();
       const value=check.checked?null:Number(amount.value);
       if(!check.checked&&(!amount.value.trim()||!Number.isSafeInteger(value)||
          value<0||value<(p.stock?.allocated||0))){
         report('Quantità non valida per '+p.name+
           '. Non puoi scendere sotto la quantità già prenotata.',true);
         return;
       }
       button.disabled=true;report('Salvataggio scorte di '+p.name+'…');
       const payload={school_id:bar.school_id,bar_id:bar.id,product_id:p.id,
         service_date:day,capacity:value};
       const result=p.stock
         ?await client.from('daily_stock').update({capacity:value})
           .eq('id',p.stock.id).eq('school_id',bar.school_id)
           .eq('bar_id',bar.id).select('id').single()
         :await client.from('daily_stock').insert(payload).select('id').single();
       if(result.error){
         report(result.error.message,true);button.disabled=false;return;
       }
       await sync();
     });
     row.append(info,form);list.append(row);
   }
 }
 async function loadContext(detail){
   version++;context=detail;bars=[];items=[];select.replaceChildren();
   empty('Verifica permessi in corso…');
   if(!user||!detail||!['warehouse_manager','school_admin'].includes(detail.role)
      ||!detail.schoolId){panel.hidden=true;return;}
   const [m,assurance]=await Promise.all([
     client.from('school_memberships').select('school_id,role_assignments(role_code)')
       .eq('user_id',user.id).eq('school_id',detail.schoolId)
       .eq('membership_status','active'),
     client.auth.mfa.getAuthenticatorAssuranceLevel()
   ]);
   const adminVerified=detail.role==='school_admin'
      && !assurance.error&&assurance.data.currentLevel==='aal2';
   const valid=!m.error&&(m.data||[]).some(row=>
     (row.role_assignments||[]).some(r=>
       r.role_code===detail.role && (detail.role==='warehouse_manager'||adminVerified)));
   if(!valid){panel.hidden=true;report('Permessi per il magazzino non verificati.',true);return;}
   const b=await client.from('bars').select('id,school_id,name')
     .eq('school_id',detail.schoolId).eq('is_active',true).order('name');
   if(b.error){report(b.error.message,true);return;}
   bars=b.data||[];
   for(const bar of bars)select.add(new Option(bar.name,bar.id));
   panel.hidden=false;
   if(bars.length)await sync();
   else empty('Non ci sono bar attivi nella scuola.');
 }
 select.addEventListener('change',()=>void sync());
 date.addEventListener('change',()=>void sync());
 byId('warehouse-refresh').addEventListener('click',()=>void sync());
 window.addEventListener('breakapp:workspace-context',event=>{
   void loadContext(event.detail);
 });
 window.addEventListener('breakapp:route-changed',event=>{
   if(event.detail.route==='warehouse-inventory'&&bars.length)void sync();
 });
 client.auth.onAuthStateChange((_e,session)=>queueMicrotask(()=>{
   user=session?.user||null;
   if(!user){version++;panel.hidden=true;bars=[];list.replaceChildren();}
 }));
 client.auth.getUser().then(({data,error})=>{if(!error)user=data?.user||null;});
}
