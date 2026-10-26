import { getAdminSchools } from '../catalog/utils.js';

const make=(tag,text='')=>{const e=document.createElement(tag);e.textContent=text;return e;};
export function initializeAdminOrderSetup(client) {
  const panel=document.querySelector('#admin-order-setup');
  const school=document.querySelector('#ops-school');
  const bar=document.querySelector('#ops-bar');
  const status=document.querySelector('#ops-status');
  const schoolForm=document.querySelector('#ops-school-form');
  const slotForm=document.querySelector('#ops-slot-form');
  const slotList=document.querySelector('#ops-slot-list');
  const stockForm=document.querySelector('#ops-stock-form');
  const stockList=document.querySelector('#ops-stock-list');
  const productSelect=document.querySelector('#ops-product');
  const day=document.querySelector('#ops-stock-date');
  let access=null,windows=[],products=[],stock=[];
  const tell=(message,error=false)=>{status.textContent=message;status.dataset.type=error?'error':'information';};

  function current() {return {school_id:school.value,bar_id:bar.value};}
  function enableForms(value){
    [...schoolForm.querySelectorAll('input,button'),...slotForm.querySelectorAll('input,button'),
      ...stockForm.querySelectorAll('input,button,select')].forEach(e=>{e.disabled=!value;});
  }
  function fillBars(){
    const old=bar.value;
    bar.replaceChildren();
    for(const b of access?.bars||[]){
      if(b.school_id===school.value)bar.add(new Option(b.name,b.id));
    }
    if([...bar.options].some(o=>o.value===old))bar.value=old;
  }
  async function readSettings(){
    if(!school.value)return;
    const {data,error}=await client.from('schools')
      .select('latitude,longitude,pickup_radius_m,booking_horizon_days,cancel_cutoff_minutes,max_unpaid_orders_per_customer,approval_product_threshold,approval_amount_threshold_cents')
      .eq('id',school.value).single();
    if(error){tell(error.message,true);return;}
    const values={
      'ops-latitude':data.latitude,
      'ops-longitude':data.longitude,
      'ops-radius':data.pickup_radius_m,
      'ops-horizon':data.booking_horizon_days,
      'ops-cutoff':data.cancel_cutoff_minutes,
      'ops-max-unpaid':data.max_unpaid_orders_per_customer,
      'ops-approval-items':data.approval_product_threshold,
      'ops-approval-eur':data.approval_amount_threshold_cents==null?null:(data.approval_amount_threshold_cents/100)
    };
    for(const [id,value] of Object.entries(values))document.getElementById(id).value=value??'';
  }
  function render(){
    slotList.replaceChildren();
    for(const w of windows){
      const row=make('div');row.className='catalog-item';
      row.append(make('span',`${w.service_date} · ${w.starts_at.slice(0,5)}–${w.ends_at.slice(0,5)} · ${w.is_active?'Attiva':'Disattiva'}`));
      const btn=make('button',w.is_active?'Disattiva':'Attiva');
      btn.type='button';btn.className='button button-outline button-small';
      btn.addEventListener('click',async()=>{
        btn.disabled=true;
        const {error}=await client.from('pickup_windows').update({is_active:!w.is_active}).eq('id',w.id);
        if(error){tell(error.message,true);btn.disabled=false;return;}
        await refresh();
      });
      row.append(btn);slotList.append(row);
    }
    if(!windows.length)slotList.append(make('p','Nessuna fascia configurata per il bar.'));
    productSelect.replaceChildren();
    for(const p of products)productSelect.add(new Option(p.name+(p.is_active?'':' · Nascosto'),p.id));
    stockList.replaceChildren();
    for(const s of stock){
      const name=products.find(p=>p.id===s.product_id)?.name||'Prodotto';
      const capacity=s.capacity===null?'Illimitata':`${s.capacity}`;
      stockList.append(make('p',`${s.service_date} · ${name}: capacità ${capacity}, già allocati ${s.allocated}`));
    }
    if(!stock.length)stockList.append(make('p','Nessuna quantità configurata per questo giorno.'));
  }
  async function refresh(){
    if(!access||!bar.value)return;
    const {school_id,bar_id}=current();
    tell('Caricamento impostazioni dal database...');
    const [slots,pros,availability]=await Promise.all([
      client.from('pickup_windows').select('id,service_date,starts_at,ends_at,is_active')
        .eq('school_id',school_id).eq('bar_id',bar_id).order('service_date',{ascending:true}).order('starts_at',{ascending:true}).limit(80),
      client.from('products').select('id,name,is_active').eq('school_id',school_id).eq('bar_id',bar_id).order('name'),
      client.from('daily_stock').select('id,product_id,service_date,capacity,allocated')
        .eq('school_id',school_id).eq('bar_id',bar_id).eq('service_date',day.value||'1900-01-01').order('product_id')
    ]);
    const failure=slots.error||pros.error||availability.error;
    if(failure){
      enableForms(false);
      tell('Configurazione operativa non disponibile: '+failure.message+' (verifica migrazione SQL 04).',true);
      return;
    }
    windows=slots.data||[];products=pros.data||[];stock=availability.data||[];
    enableForms(true);render();tell('Configurazione del bar aggiornata.');
  }
  schoolForm.addEventListener('submit',async event=>{
    event.preventDefault();if(!schoolForm.reportValidity())return;
    const val=id=>document.getElementById(id).value.trim();
    const nullable=id=>val(id)?Number(val(id)):null;
    const params={
      p_school_id:school.value,
      p_latitude:Number(val('ops-latitude')),p_longitude:Number(val('ops-longitude')),
      p_radius_m:Number(val('ops-radius')),p_horizon_days:Number(val('ops-horizon')),
      p_cancel_cutoff_minutes:Number(val('ops-cutoff')),
      p_max_unpaid:Number(val('ops-max-unpaid')),
      p_approval_product_threshold:nullable('ops-approval-items'),
      p_approval_amount_threshold_cents:val('ops-approval-eur')?
        Math.round(Number(val('ops-approval-eur').replace(',','.'))*100):null
    };
    if(!Number.isFinite(params.p_latitude)||!Number.isFinite(params.p_longitude))return tell('Coordinate obbligatorie.',true);
    tell('Salvataggio delle regole sul server…');
    const {error}=await client.rpc('configure_school_booking',params);
    if(error)tell(error.message,true);
    else{tell('Regole scuola salvate.');await readSettings();}
  });
  slotForm.addEventListener('submit',async event=>{
    event.preventDefault();if(!slotForm.reportValidity())return;
    const {school_id,bar_id}=current();
    const {error}=await client.from('pickup_windows').insert({
      school_id,bar_id,service_date:document.querySelector('#ops-slot-date').value,
      starts_at:document.querySelector('#ops-slot-start').value,
      ends_at:document.querySelector('#ops-slot-end').value,is_active:true
    });
    if(error)return tell(error.message,true);
    tell('Fascia di ritiro creata.');await refresh();
  });
  stockForm.addEventListener('submit',async event=>{
    event.preventDefault();if(!stockForm.reportValidity())return;
    const {school_id,bar_id}=current();
    const product_id=productSelect.value;
    if(!product_id)return tell('Prima crea un prodotto nel catalogo.',true);
    const raw=document.querySelector('#ops-capacity').value.trim();
    const capacity=raw===''?null:Number(raw);
    if(capacity!==null&&(!Number.isInteger(capacity)||capacity<0))return tell('Capacità non valida.',true);
    const service_date=day.value;
    const existing=stock.find(s=>s.product_id===product_id&&s.service_date===service_date);
    const result=existing
      ?await client.from('daily_stock').update({capacity}).eq('id',existing.id)
      :await client.from('daily_stock').insert({school_id,bar_id,product_id,service_date,capacity});
    if(result.error)return tell(result.error.message,true);
    tell('Scorte giornaliere salvate.');await refresh();
  });
  school.addEventListener('change',()=>{fillBars();void readSettings();void refresh();});
  bar.addEventListener('change',()=>{void refresh();});
  day.addEventListener('change',()=>{void refresh();});
  document.querySelector('#ops-refresh').addEventListener('click',()=>{void readSettings();void refresh();});
  function hide(){
    panel.hidden=true;access=null;windows=[];products=[];stock=[];
    school.replaceChildren();bar.replaceChildren();slotList.replaceChildren();stockList.replaceChildren();
  }
  async function show(nextAccess){
    const admins=getAdminSchools(nextAccess);
    if(!admins.length){hide();return;}
    access=nextAccess;
    school.replaceChildren();
    for(const s of admins)school.add(new Option(s.name,s.id));
    fillBars();
    panel.hidden=false;
    enableForms(false);
    await readSettings();
    await refresh();
  }
  return {show,hide};
}
