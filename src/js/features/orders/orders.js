import { cartAdd, cartSetQuantity, cartSummary, toRpcItems } from './cart-core.js';
import { formatEuro } from '../catalog/utils.js';

const elem = (tag, text='', cls='') => {
  const node=document.createElement(tag); node.className=cls; node.textContent=text; return node;
};
const report=(node,msg,error=false)=>{
  node.textContent=msg; node.dataset.type=error?'error':'information';
};
function positionOnce() {
  return new Promise((resolve,reject)=>{
    if (!navigator.geolocation) return reject(new Error('Geolocalizzazione non disponibile'));
    navigator.geolocation.getCurrentPosition(resolve,()=>reject(new Error('Per ordinare, consenti la posizione GPS e riprova.')),
      {enableHighAccuracy:true,maximumAge:0,timeout:20000});
  });
}
export function initializeOrders(client) {
  if (!client) return;
  const section=document.querySelector('#orders');
  const staffPanel=document.querySelector('#staff-orders-section');
  const feedback=document.querySelector('#orders-feedback');
  const history=document.querySelector('#orders-list');
  const staffFeedback=document.querySelector('#staff-orders-feedback');
  const staffList=document.querySelector('#staff-orders-list');
  const productDialog=document.querySelector('#product-dialog');
  const cartDialog=document.querySelector('#cart-dialog');
  const cartBar=document.querySelector('#cart-strip');
  const cartLines=document.querySelector('#cart-lines');
  const cartMessage=document.querySelector('#cart-feedback');
  const stepper=document.querySelector('#order-stepper');
  const stepLabel=document.querySelector('#order-step-label');
  const slotSelect=document.querySelector('#order-window');
  const checkoutFeedback=document.querySelector('#order-checkout-feedback');
  const checkoutReview=document.querySelector('#order-review');
  const orderNext=document.querySelector('#order-next');
  const orderBack=document.querySelector('#order-back');
  const orderSubmit=document.querySelector('#order-submit');
  let user=null, context={schoolId:'',barId:'',products:[]}, cart=[], product=null;
  let step=1,windows=[], enabled=false, requestKey=null, staffSchools=[],version=0;
  let staffOrders=[];

  function total(){return cartSummary(cart,context.products);}
  function showCartBar(){
    if (!cart.length){cartBar.hidden=true;return;}
    try {
      const summary=total();
      document.querySelector('#cart-count').textContent=String(summary.count);
      document.querySelector('#cart-total').textContent=formatEuro(summary.totalCents);
      cartBar.hidden=false;
    } catch(err){ cart=[];cartBar.hidden=true;report(cartMessage,err.message,true); }
  }
  function changeCart(next){cart=next;requestKey=null;showCartBar();renderCart();}
  function renderCart(){
    cartLines.replaceChildren();
    const proceed=document.querySelector('#cart-checkout');
    proceed.disabled=true;
    if (!cart.length){cartLines.append(elem('p','Il tuo carrello è vuoto.'));return;}
    try {
      const sum=total();
      sum.lines.forEach(line=>{
        const row=elem('div','','order-row');
        row.append(elem('strong',line.name),elem('span',formatEuro(line.subtotalCents)));
        const actions=elem('div','','order-actions');
        for(const [label,n] of [['−',line.quantity-1],['+',line.quantity+1]]){
          const button=elem('button',label,'button button-outline button-small');
          button.type='button';button.setAttribute('aria-label',label==='+'?'Aumenta quantità':'Riduci quantità');
          button.addEventListener('click',()=>{try{changeCart(cartSetQuantity(cart,line.product_id,n));}catch(err){report(cartMessage,err.message,true);}});
          actions.append(button);
        }
        row.append(actions);cartLines.append(row);
      });
      cartLines.append(elem('strong',`Totale indicativo: ${formatEuro(sum.totalCents)}`));
      proceed.disabled=!enabled || !windows.length;
      report(cartMessage,enabled
        ? 'Il server ricalcola prezzi e scorte alla conferma.'
        : 'Prenotazioni in attesa di attivazione sul database.');
    } catch(err){report(cartMessage,err.message,true);}
  }
  window.addEventListener('breakapp:catalog-ready',event=>{
    const next=event.detail;
    if(context.barId!==next.barId||context.schoolId!==next.schoolId) cart=[];
    context=next;requestKey=null;showCartBar();
    if(cartDialog.open)renderCart();
    if(user)void fetchWindows();
  });
  window.addEventListener('breakapp:product-open',event=>{
    if(!user)return;
    product=context.products.find(p=>p.id===event.detail.id);
    if(!product)return;
    document.querySelector('#product-name').textContent=product.name;
    document.querySelector('#product-description').textContent=product.description||'Ingredienti e allergeni non ancora pubblicati.';
    document.querySelector('#product-price').textContent=formatEuro(product.price_cents);
    document.querySelector('#product-ingredients').textContent=product.ingredients
      ? 'Ingredienti: '+product.ingredients
      : 'Ingredienti non pubblicati. Verifica direttamente con il bar.';
    const allergenNames={
      gluten:'Glutine',crustaceans:'Crostacei',eggs:'Uova',fish:'Pesce',
      peanuts:'Arachidi',soy:'Soia',milk:'Latte',nuts:'Frutta a guscio',
      celery:'Sedano',mustard:'Senape',sesame:'Sesamo',sulphites:'Solfiti',
      lupin:'Lupini',molluscs:'Molluschi'
    };
    document.querySelector('#product-allergens').textContent=product.allergens?.length
      ? 'Allergeni dichiarati: '+product.allergens.map(x=>allergenNames[x]||x).join(', ')
      : 'Allergeni non dichiarati. Chiedi conferma al bar.';
    const image=document.querySelector('#product-image');
    if(product.image_path){
      image.src=client.storage.from('breakapp-product-images').getPublicUrl(product.image_path).data.publicUrl;
      image.alt='Foto di '+product.name;image.hidden=false;
    }else{image.hidden=true;image.removeAttribute('src');}
    document.querySelector('#product-quantity').value='1';
    productDialog.showModal();
  });
  document.querySelector('#product-add').addEventListener('click',()=>{
    try {
      const q=Number(document.querySelector('#product-quantity').value);
      changeCart(cartAdd(cart,product.id,q));productDialog.close();
    } catch(err){report(cartMessage,err.message,true);}
  });
  document.querySelector('#cart-open').addEventListener('click',()=>{renderCart();cartDialog.showModal();});
  async function fetchWindows(){
    const seq=++version;
    enabled=false;windows=[];slotSelect.replaceChildren();
    const banner=document.querySelector('#menu-service-alert');
    banner.hidden=true;banner.replaceChildren();
    if(!user||!context.barId)return;
    const [win,service,closures,hours]=await Promise.all([
      client.from('pickup_windows')
        .select('id,service_date,starts_at,ends_at').eq('bar_id',context.barId)
        .eq('is_active',true).order('service_date').order('starts_at').limit(150),
      client.from('bar_service_state').select('accepting_orders,reason')
        .eq('bar_id',context.barId).maybeSingle(),
      client.from('bar_closures').select('service_date,starts_at,ends_at,reopened_at')
        .eq('bar_id',context.barId).is('reopened_at',null).limit(200),
      client.from('bar_opening_hours').select('weekday,starts_at,ends_at')
        .eq('bar_id',context.barId)
    ]);
    if(seq!==version)return;
    const failure=win.error||service.error||closures.error||hours.error;
    if(failure){
      report(cartMessage,'Impossibile verificare orari o disponibilità: '+failure.message,true);
      renderCart();return;
    }
    const paused=service.data?.accepting_orders===false;
    const closed=closures.data||[],open=hours.data||[];
    const valid=(win.data||[]).filter(w=>{
      const localDow=new Date(w.service_date+'T12:00:00Z').getUTCDay();
      const opened=open.some(h=>h.weekday===localDow&&
        h.starts_at<=w.starts_at&&h.ends_at>=w.ends_at);
      const excluded=closed.some(c=>c.service_date===w.service_date
        &&c.starts_at<w.ends_at&&c.ends_at>w.starts_at);
      return opened&&!excluded;
    });
    windows=paused?[]:valid;
    enabled=!paused && windows.length>0;
    windows.forEach(w=>slotSelect.add(new Option(
      w.service_date+' · '+w.starts_at.slice(0,5)+'-'+w.ends_at.slice(0,5),w.id)));
    if(paused){
      banner.hidden=false;
      banner.textContent='Nuove prenotazioni temporaneamente sospese. Motivo: '+
        (service.data.reason||'necessità operativa')+'. Il menu rimane consultabile.';
      report(cartMessage,'Nuove prenotazioni sospese per il bar selezionato.',true);
    }else if(!windows.length){
      banner.hidden=false;
      banner.textContent='Nessuna fascia prenotabile: il bar potrebbe essere chiuso oppure le fasce non sono ancora state configurate.';
      report(cartMessage,'Nessuna fascia di ritiro attualmente prenotabile.',true);
    }
    renderCart();
  }
  window.addEventListener('breakapp:service-changed',event=>{
    if(event.detail?.barId===context.barId && user)void fetchWindows();
  });
  function drawStep(){
    stepLabel.textContent=`Passaggio ${step} di 4`;
    [...stepper.querySelectorAll('[data-step]')].forEach(x=>x.hidden=Number(x.dataset.step)!==step);
    orderBack.hidden=step===1;orderNext.hidden=step===4;orderSubmit.hidden=step!==4;
    if(step===4){
      const selected=windows.find(w=>w.id===slotSelect.value);
      const s=total();
      checkoutReview.replaceChildren(
        elem('p',`Prodotti: ${s.count} · ${formatEuro(s.totalCents)} (indicativo)`),
        elem('p',`Ritiro: ${selected?selected.service_date+' '+selected.starts_at.slice(0,5):'Non selezionato'}`),
        elem('p','Pagamento al ritiro: contanti o POS esterno presso il bar.'),
        elem('p','Per confermare, autorizza la verifica GPS. La disponibilità è verificata dal server.')
      );
    }
  }
  document.querySelector('#cart-checkout').addEventListener('click',()=>{
    if(!enabled||!windows.length)return;
    cartDialog.close();step=1;drawStep();stepper.showModal();
  });
  orderNext.addEventListener('click',()=>{
    if(step===2&&!slotSelect.value){report(checkoutFeedback,'Scegli una fascia.',true);return;}
    if(step<4){step++;drawStep();}
  });
  orderBack.addEventListener('click',()=>{if(step>1){step--;drawStep();}});
  orderSubmit.addEventListener('click',async()=>{
    if(!user||!cart.length||!slotSelect.value||!enabled)return;
    orderSubmit.disabled=true;report(checkoutFeedback,'Verifica posizione GPS…');
    try {
      const loc=await positionOnce();
      requestKey??=crypto.randomUUID();
      const {data,error}=await client.rpc('submit_individual_order',{
        p_bar_id:context.barId,p_window_id:slotSelect.value,p_items:toRpcItems(cart),
        p_request_key:requestKey,p_latitude:loc.coords.latitude,
        p_longitude:loc.coords.longitude,p_accuracy_m:loc.coords.accuracy,
        p_observed_at:new Date(loc.timestamp).toISOString()
      });
      if(error)throw error;
      if(!data)throw new Error('Conferma non ricevuta: controlla lo storico prima di riprovare.');
      changeCart([]);requestKey=null;stepper.close();
      await loadOrders();location.hash='orders';
      report(feedback,'Ordine creato correttamente sul server.');
    } catch(err){report(checkoutFeedback,err.message||'Ordine non riuscito.',true);}
    finally{orderSubmit.disabled=false;}
  });
  async function loadOrders(){
    if(!user)return;
    report(feedback,'Caricamento ordini…');
    const {data,error}=await client.from('orders')
      .select('id,display_no,pickup_token,status,payment_status,total_cents,created_at,pickup_windows(service_date,starts_at),order_items(product_name,quantity)')
      .eq('customer_id',user.id).order('created_at',{ascending:false}).limit(50);
    if(error){report(feedback,'Ordini non disponibili: '+error.message,true);return;}
    history.replaceChildren();
    for(const o of data||[]){
      const box=elem('article','','order-card');
      box.append(elem('h3',`Ordine #${o.display_no} · ${o.status}`),
        elem('p',`Ritiro ${o.pickup_windows?.service_date||'—'} ${o.pickup_windows?.starts_at?.slice(0,5)||''}`),
        elem('p',`${formatEuro(o.total_cents)} · ${o.payment_status==='paid'?'Pagato':'Da pagare'}`));
      const ul=elem('ul');(o.order_items||[]).forEach(x=>ul.append(elem('li',`${x.quantity} × ${x.product_name}`)));box.append(ul);
      if(!['cancelled','delivered','no_show'].includes(o.status) && o.pickup_token){
        const ticket=elem('button','Mostra QR di ritiro','button button-outline button-small');
        ticket.type='button';
        ticket.addEventListener('click',()=>{
          window.dispatchEvent(new CustomEvent('breakapp:pickup-ticket',{
            detail:{pickupToken:o.pickup_token,displayNo:o.display_no}
          }));
        });
        box.append(ticket);
      }
      if(o.status==='confirmed'&&o.payment_status==='due'){
        const cancel=elem('button','Annulla ordine','button button-outline button-small');
        cancel.addEventListener('click',async()=>{
          if(!confirm('Annullare definitivamente questo ordine?'))return;
          cancel.disabled=true;
          const result=await client.rpc('cancel_individual_order',{p_order_id:o.id});
          if(result.error){report(feedback,result.error.message,true);cancel.disabled=false;return;}
          await loadOrders();
        });box.append(cancel);
      }
      history.append(box);
    }
    if(!history.childElementCount)history.append(elem('p','Nessun ordine effettuato.'));
    const noticeArea=document.querySelector('#customer-service-notices');
    if(noticeArea){
      const n=await client.from('customer_notifications')
        .select('message,created_at,read_at')
        .eq('user_id',user.id).order('created_at',{ascending:false}).limit(15);
      noticeArea.replaceChildren();
      if(!n.error && n.data?.length){
        const h=elem('h3','Avvisi relativi ai tuoi ordini');
        noticeArea.append(h);
        n.data.forEach(row=>{
          const card=elem('div','','service-notice');
          card.append(elem('strong',new Date(row.created_at).toLocaleString('it-IT')),
            elem('p',row.message));noticeArea.append(card);
        });
      }
    }
    report(feedback,`Ordini caricati: ${data?.length||0}.`);
  }
  function action(box,label,callback){
    const button=elem('button',label,'button button-outline button-small');
    button.addEventListener('click',async()=>{
      button.disabled=true;
      try {
        const result=await callback();
        if(result?.error)throw result.error;
        await fetchStaffOrders();
      }catch(err){report(staffFeedback,err.message,true);button.disabled=false;}
    });box.append(button);
  }
  async function fetchStaffOrders(){
    if(!user||!staffSchools.length)return;
    const {data,error}=await client.from('orders')
      .select('id,school_id,display_no,status,payment_status,total_cents,pickup_windows(service_date,starts_at),order_items(product_name,quantity)')
      .in('school_id',staffSchools).order('created_at',{ascending:false}).limit(100);
    if(error){report(staffFeedback,error.message,true);return;}
    staffOrders=data||[];drawStaff();
  }
  function drawStaff(){
    staffList.replaceChildren();
    const q=document.querySelector('#staff-search').value.trim();
    staffOrders.filter(o=>!q||String(o.display_no).includes(q)).forEach(o=>{
      const box=elem('article','','order-card');
      box.append(elem('h3',`#${o.display_no} · ${o.status}`),
        elem('p',`Ritiro ${o.pickup_windows?.service_date} ${o.pickup_windows?.starts_at?.slice(0,5)}`),
        elem('p',`${formatEuro(o.total_cents)} · ${o.payment_status==='paid'?'Pagato':'Da incassare'}`));
      const ul=elem('ul');(o.order_items||[]).forEach(x=>ul.append(elem('li',`${x.quantity} × ${x.product_name}`)));box.append(ul);
      const actions=elem('div','','order-actions');
      if(o.status==='confirmed'){
        action(actions,'Prepara',()=>client.rpc('advance_individual_order',{p_order_id:o.id,p_next:'preparing'}));
        action(actions,'Pronto',()=>client.rpc('advance_individual_order',{p_order_id:o.id,p_next:'ready'}));
      }
      if(o.status==='preparing')action(actions,'Pronto',()=>client.rpc('advance_individual_order',{p_order_id:o.id,p_next:'ready'}));
      if(o.status==='ready'&&o.payment_status==='due'){
        for(const [label,method] of [['Incassa contanti','cash'],['POS esterno','external_pos']]){
          action(actions,label,async()=>{
            if(!confirm(`Confermi di aver effettivamente ricevuto ${formatEuro(o.total_cents)} tramite ${label}?`))return {error:new Error('Operazione annullata')};
            return client.rpc('record_individual_counter_payment',{p_order_id:o.id,p_method:method,p_request_key:crypto.randomUUID()});
          });
        }
      }
      if(o.status==='ready'&&o.payment_status==='paid'){
        action(actions,'Consegna',async()=>{
          if(!confirm('Confermi che tutti i prodotti sono stati consegnati?'))return {error:new Error('Operazione annullata')};
          return client.rpc('advance_individual_order',{p_order_id:o.id,p_next:'delivered'});
        });
      }
      box.append(actions);staffList.append(box);
    });
    if(!staffList.childElementCount)staffList.append(elem('p','Nessun ordine trovato.'));
  }
  async function checkStaff(){
    staffSchools=[];staffPanel.hidden=true;
    if(!user)return;
    const {data,error}=await client.from('school_memberships')
      .select('school_id,role_assignments(role_code)').eq('user_id',user.id).eq('membership_status','active');
    if(error)return;
    const assurance=await client.auth.mfa.getAuthenticatorAssuranceLevel();
    const adminVerified=!assurance.error&&assurance.data.currentLevel==='aal2';
    staffSchools=(data||[]).filter(m=>(m.role_assignments||[]).some(r=>r.role_code==='bartender'||(r.role_code==='school_admin'&&adminVerified)))
      .map(m=>m.school_id);
    staffPanel.hidden=!staffSchools.length;
    if(staffSchools.length)await fetchStaffOrders();
  }
  document.querySelector('#orders-refresh').addEventListener('click',()=>void loadOrders());
  document.querySelector('#staff-refresh').addEventListener('click',()=>void checkStaff());
  document.querySelector('#staff-search').addEventListener('input',drawStaff);
  function setUser(next){
    const changed=user?.id!==next?.id;user=next;section.hidden=!user;
    if(!user){staffPanel.hidden=true;cart=[];showCartBar();return;}
    if(changed){cart=[];showCartBar();void fetchWindows();void loadOrders();void checkStaff();}
  }
  client.auth.onAuthStateChange((_event,session)=>queueMicrotask(()=>setUser(session?.user||null)));
  client.auth.getUser().then(({data,error})=>{if(!error)setUser(data?.user||null);});
}
