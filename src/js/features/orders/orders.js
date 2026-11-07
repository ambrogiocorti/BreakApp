import { cartAdd, cartSetQuantity, cartSummary, toRpcItems } from './cart-core.js';
import { formatEuro } from '../catalog/utils.js';
import { orderStatusLabel, slotLabel, availableSlots, boardOrders, productionTotals, windowLabel, orderStatusTone, paymentState } from './staff-board.js';
import { accuratePosition } from '../../core/geolocation.js';
import { paymentError } from '../../core/payment-error.js';
import { confirmDialog, toast } from '../../core/dialog.js';
import { friendlyError } from '../../core/errors.js';
import { showLocation, locationProblem } from '../../core/location-ui.js';

const elem = (tag, text='', cls='') => {
  const node=document.createElement(tag); node.className=cls; node.textContent=text; return node;
};
const report=(node,msg,error=false)=>{
  node.textContent=error?friendlyError(msg):msg; node.dataset.type=error?'error':'information';
};
const badge=(text,tone)=>{const node=elem('span',text,'status');node.dataset.tone=tone;return node;};
function positionOnce(signal) {
  return accuratePosition({signal,onProgress:accuracy=>showLocation(
    document.querySelector('#order-location'),'improving',
    {detail:'Precisione attuale: circa ±'+accuracy+' m (serve entro 100 m).'})});
}
export function initializeOrders(client) {
  if (!client) return;
  const section=document.querySelector('#orders');
  const staffPanel=document.querySelector('#staff-orders-section');
  const feedback=document.querySelector('#orders-feedback');
  const history=document.querySelector('#orders-list');
  const staffFeedback=document.querySelector('#staff-orders-feedback');
  const staffList=document.querySelector('#staff-orders-list');
  const staffSlotFilter=document.querySelector('#staff-slot-filter');
  const staffVisibilityFilter=document.querySelector('#staff-visibility-filter');
  const staffLiveStatus=document.querySelector('#staff-live-status');
  const staffProduction=document.querySelector('#staff-production-list');
  const staffProductionTotal=document.querySelector('#staff-production-total');
  const actionDialog=document.querySelector('#staff-action-confirm');
  const actionSummary=document.querySelector('#staff-action-summary');
  let activeDecision=null;
  function decideStaffAction(message){
    if(actionDialog.open)return Promise.resolve(false);
    actionSummary.textContent=message;
    actionDialog.showModal();
    return new Promise(resolve=>{activeDecision=resolve;});
  }
  function finishStaffDecision(result){
    const resolve=activeDecision;
    activeDecision=null;
    if(actionDialog.open)actionDialog.close();
    if(resolve)resolve(result);
  }
  document.querySelector('#staff-action-cancel').addEventListener('click',()=>finishStaffDecision(false));
  document.querySelector('#staff-action-form').addEventListener('submit',event=>{
    event.preventDefault();finishStaffDecision(true);
  });
  actionDialog.addEventListener('close',()=>{
    if(activeDecision)finishStaffDecision(false);
  });

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
  let step=2,windows=[], enabled=false, requestKey=null, staffSchools=[],version=0,locationAbort=null;
  let staffOrders=[];
  let staffContextSchool=null;
  let staffFetchSequence=0,staffAuthVersion=0;
  const STAFF_PAGE_SIZE=250,STAFF_MAX_PAGES=8;
  const STAFF_FIELDS='id,school_id,display_no,status,payment_status,payment_method,total_cents,pickup_windows(service_date,starts_at),order_items(product_name,quantity)';
  let staffChannels=[],staffFallbackTimer=null,staffDebounceTimer=null;
  function stopStaffFeed(){
    clearInterval(staffFallbackTimer);
    clearTimeout(staffDebounceTimer);
    staffFallbackTimer=null;staffDebounceTimer=null;
    for(const channel of staffChannels)void client.removeChannel(channel);
    staffChannels=[];
  }
  function queueStaffRefresh(){
    if(!user||!staffSchools.length||document.hidden||!navigator.onLine)return;
    clearTimeout(staffDebounceTimer);
    staffDebounceTimer=setTimeout(()=>{void fetchStaffOrders();},350);
  }
  function startStaffFeed(){
    stopStaffFeed();
    if(!user||!staffSchools.length)return;
    const identity=user.id;
    const schools=staffContextSchool&&staffSchools.includes(staffContextSchool)
      ?[staffContextSchool]:staffSchools;
    for(const school of [...new Set(schools)]){
      const channel=client.channel('banco-'+identity+'-'+school);
      const config={schema:'public',table:'orders',filter:'school_id=eq.'+school};
      channel.on('postgres_changes',{...config,event:'INSERT'},queueStaffRefresh)
        .on('postgres_changes',{...config,event:'UPDATE'},queueStaffRefresh)
        .subscribe(status=>{
          if(user?.id!==identity)return;
          if(status==='SUBSCRIBED'){staffLiveStatus.textContent='In tempo reale';staffLiveStatus.dataset.state='live';}
          else if(['CHANNEL_ERROR','TIMED_OUT','CLOSED'].includes(status)){
            staffLiveStatus.textContent='Tempo reale non disponibile · aggiornamento ogni 15 s';staffLiveStatus.dataset.state='error';}
        });
      staffChannels.push(channel);
    }
    // Realtime alone is not an availability guarantee: recover lost events.
    staffFallbackTimer=setInterval(()=>{
      if(user?.id===identity)queueStaffRefresh();
    },15000);
  }
  document.addEventListener('visibilitychange',()=>{
    if(!document.hidden)queueStaffRefresh();
  });
  window.addEventListener('online',queueStaffRefresh);

  const stripeAttemptKeys=new Map();
  const stripeRefundKeys=new Map();
  const refundDialog=document.querySelector('#staff-refund-dialog');
  const refundForm=document.querySelector('#staff-refund-form');
  const refundSummary=document.querySelector('#staff-refund-summary');
  const refundReason=document.querySelector('#staff-refund-reason');
  const refundFeedback=document.querySelector('#staff-refund-feedback');
  const refundConfirm=document.querySelector('#staff-refund-confirm');
  const refundSubmit=document.querySelector('#staff-refund-submit');
  let selectedRefund=null;
  const cashRefundList=document.querySelector('#staff-cash-refunds-list');
  const cashRefundFeedback=document.querySelector('#staff-cash-refunds-feedback');
  const cashReturnDialog=document.querySelector('#staff-cash-return-dialog');
  const cashReturnForm=document.querySelector('#staff-cash-return-form');
  const cashReturnSummary=document.querySelector('#staff-cash-return-summary');
  const cashReturnReason=document.querySelector('#staff-cash-return-reason');
  const cashReturnFeedback=document.querySelector('#staff-cash-return-feedback');
  const cashReturnSubmit=document.querySelector('#staff-cash-return-submit');
  let cashRefunds=[],selectedCashRefund=null,cashRefundVersion=0;
  document.querySelector('#staff-cash-return-cancel').addEventListener('click',()=>cashReturnDialog.close());
  cashReturnDialog.addEventListener('close',()=>{
    selectedCashRefund=null;cashReturnForm.reset();cashReturnFeedback.textContent='';
  });
  cashReturnForm.addEventListener('submit',async event=>{
    event.preventDefault();
    const obligation=selectedCashRefund;
    if(!user||!obligation||cashReturnSubmit.disabled||!cashReturnForm.reportValidity())return;
    if(!staffSchools.includes(obligation.school_id)||obligation.status==='returned'){
      report(cashReturnFeedback,'Restituzione non più disponibile: aggiorna la lista.',true);return;
    }
    const actor=user.id;
    cashReturnSubmit.disabled=true;
    report(cashReturnFeedback,'Registrazione della restituzione in cassa…');
    try{
      const {error}=await client.rpc('confirm_cash_refund_return',{
        p_refund:obligation.id,p_reason:cashReturnReason.value.trim()
      });
      if(error)throw error;
      if(user?.id!==actor)return;
      cashReturnDialog.close();
      report(staffFeedback,'Restituzione di '+formatEuro(obligation.amount_cents)+' registrata in cassa. Il movimento è salvato dal server.');
      await fetchStaffOrders();
    }catch(error){
      if(user?.id===actor)report(cashReturnFeedback,
        'Restituzione non confermata: '+(error?.message||'errore sconosciuto')+
        '. Se hai già consegnato il denaro, verifica i movimenti di cassa prima di riprovare.',true);
    }finally{cashReturnSubmit.disabled=false;}
  });
  document.querySelector('#staff-refund-cancel').addEventListener('click',()=>refundDialog.close());
  refundDialog.addEventListener('close',()=>{selectedRefund=null;refundForm.reset();refundFeedback.textContent='';});
  refundForm.addEventListener('submit',async event=>{
    event.preventDefault();
    const o=selectedRefund;
    if(!user||!o||!refundForm.reportValidity()||refundSubmit.disabled)return;
    if(!staffSchools.includes(o.school_id)||!['delivered','no_show'].includes(o.status)||o.payment_status!=='paid'){
      report(refundFeedback,'L’ordine non è più rimborsabile. Aggiorna la lista.',true);return;
    }
    refundSubmit.disabled=true;
    report(refundFeedback,'Registrazione della richiesta di rimborso…');
    const key=stripeRefundKeys.get(o.id)||crypto.randomUUID();
    stripeRefundKeys.set(o.id,key);
    try{
      const {data,error}=await client.rpc('request_completed_order_refund',{
        p_kind:'individual',p_order:o.id,p_key:key,p_reason:refundReason.value.trim()
      });
      if(error)throw error;
      const online=Array.isArray(data?.online)?data.online:[];
      const cash=Number(data?.cash_pending||0);
      if(!online.length&&!cash)throw new Error('Il server non ha restituito un credito rimborsabile.');
      stripeRefundKeys.delete(o.id);
      refundDialog.close();
      const parts=[];
      if(online.length)parts.push('Rimborso Stripe richiesto: '+online.length+' transazione/i in elaborazione. L’esito definitivo sarà confermato dal webhook.');
      if(cash>0)parts.push('Restituzione al banco/POS esterno da effettuare e registrare in cassa: '+formatEuro(cash)+'. Non risulta ancora restituita.');
      report(staffFeedback,parts.join(' '));
      await fetchStaffOrders();
    }catch(e){
      report(refundFeedback,'Rimborso non registrato o esito incerto: '+(e?.message||'riprovare verificando prima lo stato ordine')+'. In caso di errore di rete, riprova dalla stessa finestra.',true);
    }finally{refundSubmit.disabled=false;}
  });
  const couponDisclosure=elem('details','','checkout-coupon');
  const couponLabel=elem('label','Codice sconto');
  couponLabel.htmlFor='order-coupon';
  const coupon=document.createElement('input');
  coupon.id='order-coupon';coupon.maxLength=32;coupon.placeholder='Inserisci un codice sconto';
  couponLabel.append(coupon);
  couponDisclosure.append(elem('summary','Hai un codice sconto?'),couponLabel);
  checkoutReview.parentElement.insertBefore(couponDisclosure,checkoutReview);
  const favorite=elem('button','Aggiungi ai preferiti','button button-outline button-small');favorite.type='button';productDialog.append(favorite);
  const favoriteStatus=elem('p');favoriteStatus.setAttribute('role','status');productDialog.append(favoriteStatus);
  const favoritesBox=elem('section','','panel favorites-card');favoritesBox.setAttribute('aria-label','Preferiti');section.append(favoritesBox);
  async function loadFavorites(){
    if(!user){favoritesBox.replaceChildren();return;}
    const uid=user.id,r=await client.from('customer_favorites').select('product_id,products(id,name,bar_id,price_cents)').eq('user_id',uid);
    if(user?.id!==uid)return;favoritesBox.replaceChildren(elem('h2','Preferiti'));
    const chips=elem('div');favoritesBox.append(chips);
    if(r.error){favoritesBox.append(elem('p',friendlyError(r.error),'help'));return;}
    if(!r.data?.length){favoritesBox.hidden=true;return;}
    favoritesBox.hidden=false;
    for(const row of r.data||[]){const p=row.products;if(!p)continue;
      const b=elem('button',p.name+' · '+formatEuro(p.price_cents),'button button-outline button-small');b.type='button';
      b.addEventListener('click',()=>{
        if(context.barId!==p.bar_id)return report(feedback,'Seleziona nel menu il bar del prodotto '+p.name+'.',true);
        window.dispatchEvent(new CustomEvent('breakapp:product-open',{detail:{id:p.id}}));
      });chips.append(b);
    }
  }
  favorite.addEventListener('click',async()=>{
    if(!user||!product)return;favorite.disabled=true;const uid=user.id,pid=product.id;
    try{
      const current=await client.from('customer_favorites').select('product_id').eq('user_id',uid).eq('product_id',pid).maybeSingle();if(current.error)throw current.error;
      const r=current.data?await client.from('customer_favorites').delete().eq('user_id',uid).eq('product_id',pid):await client.from('customer_favorites').insert({user_id:uid,product_id:pid});
      if(r.error)throw r.error;report(favoriteStatus,current.data?'Rimosso dai preferiti.':'Aggiunto ai preferiti.');favorite.textContent=current.data?'Aggiungi ai preferiti':'Togli dai preferiti';await loadFavorites();
    }catch(error){report(favoriteStatus,error.message,true);}finally{favorite.disabled=false;}
  });

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
  function announceCart(){
    window.dispatchEvent(new CustomEvent('breakapp:cart-changed',{detail:{barId:context.barId,
      quantities:Object.fromEntries(cart.map(x=>[x.product_id,x.quantity]))}}));
  }
  function changeCart(next){cart=next;requestKey=null;showCartBar();renderCart();announceCart();}
  function renderCart(){
    cartLines.replaceChildren();
    const proceed=document.querySelector('#cart-checkout');
    proceed.disabled=true;
    if (!cart.length){cartLines.append(elem('p','Il carrello è vuoto. Aggiungi qualcosa dal menu.'));report(cartMessage,'');return;}
    try {
      const sum=total();
      sum.lines.forEach(line=>{
        const row=elem('div','','cart-line');
        row.append(elem('strong',line.name,'cart-line-name'),
          elem('span',formatEuro(line.subtotalCents),'cart-line-price'),
          elem('span',line.quantity>1?formatEuro(Math.round(line.subtotalCents/line.quantity))+' l’uno':'','cart-line-unit'));
        const actions=elem('div','','stepper');
        const quantity=elem('output',String(line.quantity));quantity.setAttribute('aria-label','Quantità di '+line.name);
        for(const [label,n] of [['−',line.quantity-1],['+',line.quantity+1]]){
          const button=elem('button',label);
          button.type='button';button.setAttribute('aria-label',(label==='+'?'Aggiungi uno: ':n===0?'Togli dal carrello: ':'Togli uno: ')+line.name);
          button.addEventListener('click',()=>{try{changeCart(cartSetQuantity(cart,line.product_id,n));cartLines.querySelector('.cart-line:nth-child('+(sum.lines.indexOf(line)+1)+') button:'+(label==='+'?'last-of-type':'first-of-type'))?.focus();}catch(err){report(cartMessage,err.message,true);}});
          actions.append(button);
          if(label==='−')actions.append(quantity);
        }
        row.append(actions);cartLines.append(row);
      });
      const totalRow=elem('div','','cart-total');
      const label=elem('span','Totale');label.append(elem('small','Confermato dal bar alla prenotazione'));
      totalRow.append(label,elem('strong',formatEuro(sum.totalCents)));
      cartLines.append(totalRow);
      proceed.disabled=!enabled || !windows.length;
      if(enabled)report(cartMessage,'');
      else if(!cartMessage.textContent||cartMessage.dataset.type!=='error')report(cartMessage,'Le prenotazioni per questo bar non sono ancora attive.',true);
    } catch(err){report(cartMessage,err.message,true);}
  }
  window.addEventListener('breakapp:catalog-ready',event=>{
    const next=event.detail;
    if(context.barId!==next.barId||context.schoolId!==next.schoolId) cart=[];
    context=next;requestKey=null;showCartBar();
    if(cartDialog.open)renderCart();
    if(user)void fetchWindows();
  });
  window.addEventListener('breakapp:quick-add',event=>{
    const id=event.detail?.id,barId=event.detail?.barId;
    if(!id||barId!==context.barId)return;
    if(!user){
      window.dispatchEvent(new CustomEvent('breakapp:product-open',{detail:{id}}));
      return;
    }
    const product=context.products.find(p=>p.id===id && p.is_active);
    const status=document.querySelector('#menu-status');
    if(!product)return report(status,'Questo prodotto non è più disponibile. Aggiorna il menu.',true);
    try{
      if(!cart.some(x=>x.product_id===id)&&cart.length>=100)
        throw new Error('Il carrello contiene già il numero massimo di prodotti.');
      changeCart(cartAdd(cart,id,1));
      toast(product.name+' nel carrello');
    }catch(error){report(status,error?.message||'Impossibile aggiungere il prodotto.',true);}
  });
  window.addEventListener('breakapp:quick-set',event=>{
    const id=event.detail?.id,barId=event.detail?.barId,quantity=Number(event.detail?.quantity);
    if(!user||!id||barId!==context.barId||!Number.isSafeInteger(quantity))return;
    try{changeCart(cartSetQuantity(cart,id,quantity));}
    catch(error){report(document.querySelector('#menu-status'),error?.message||'Quantità non aggiornata.',true);}
  });
  window.addEventListener('breakapp:product-open',event=>{
    if(!user)return;
    favoriteStatus.textContent='';
    product=context.products.find(p=>p.id===event.detail.id);
    if(!product)return;
    document.querySelector('#product-name').textContent=product.name;
    const description=document.querySelector('#product-description');
    description.textContent=product.description||'';description.hidden=!product.description;
    document.querySelector('#product-price').textContent=formatEuro(product.price_cents);
    document.querySelector('#product-ingredients').textContent=product.ingredients
      ? product.ingredients
      : 'Non pubblicati. Chiedi al bar.';
    const allergenNames={
      gluten:'Glutine',crustaceans:'Crostacei',eggs:'Uova',fish:'Pesce',
      peanuts:'Arachidi',soy:'Soia',milk:'Latte',nuts:'Frutta a guscio',
      celery:'Sedano',mustard:'Senape',sesame:'Sesamo',sulphites:'Solfiti',
      lupin:'Lupini',molluscs:'Molluschi'
    };
    document.querySelector('#product-allergens').textContent=product.allergens?.length
      ? product.allergens.map(x=>allergenNames[x]||x).join(', ')+'. Possibili tracce: chiedi al bar.'
      : 'Non dichiarati. Chiedi conferma al bar.';
    const inCart=cart.find(x=>x.product_id===product.id)?.quantity||0;
    document.querySelector('#product-add').textContent=inCart?'Aggiungi (nel carrello: '+inCart+')':'Aggiungi al carrello';
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
    windows.forEach(w=>slotSelect.add(new Option(windowLabel(w),w.id)));
    renderSlotOptions();
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
  // Visible slot picker; the native select stays the source of truth.
  const slotOptions=elem('div','','slot-options');slotOptions.setAttribute('role','radiogroup');
  slotOptions.setAttribute('aria-label','Fascia di ritiro');
  slotSelect.after(slotOptions);slotSelect.classList.add('is-enhanced');slotSelect.tabIndex=-1;slotSelect.setAttribute('aria-hidden','true');
  function renderSlotOptions(){
    slotOptions.replaceChildren();
    let day='';
    for(const w of windows){
      const [when,time]=windowLabel(w).split(' · ');
      if(when!==day){day=when;slotOptions.append(elem('p',when,'slot-day'));}
      const option=elem('label','','slot-option');
      const radio=document.createElement('input');radio.type='radio';radio.name='order-window-choice';radio.value=w.id;
      radio.checked=slotSelect.value===w.id;
      radio.addEventListener('change',()=>{if(radio.checked){slotSelect.value=w.id;report(checkoutFeedback,'');}});
      option.append(radio,elem('strong',time));
      option.setAttribute('aria-label',when+', '+time);
      slotOptions.append(option);
    }
  }
  function drawStep(){
    stepLabel.textContent=step===2?'Passaggio 1 di 2':'Passaggio 2 di 2';
    document.querySelector('#stepper-title').textContent=step===2?'Quando ritiri?':'Controlla e conferma';
    [...stepper.querySelectorAll('[data-step]')].forEach(x=>x.hidden=Number(x.dataset.step)!==step);
    couponDisclosure.hidden=step!==4;
    orderBack.hidden=step===2;orderNext.hidden=step===4;orderSubmit.hidden=step!==4;
    if(step===2)renderSlotOptions();
    if(step===4){
      const selected=windows.find(w=>w.id===slotSelect.value);
      const s=total();
      const lines=elem('ul','','review-list');
      for(const line of s.lines){const li=elem('li');li.append(elem('span',line.quantity+'× '+line.name),elem('span',formatEuro(line.subtotalCents)));lines.append(li);}
      const facts=elem('dl','','review-facts');
      for(const [term,value] of [['Ritiro',selected?windowLabel(selected):'Non selezionato'],['Pagamento','Al banco, in contanti o POS']]){
        const row=elem('div');row.append(elem('dt',term),elem('dd',value));facts.append(row);
      }
      const totalRow=elem('div','','review-total');
      const label=elem('span','Totale');label.append(elem('small','Il bar conferma prezzi e disponibilità'));
      totalRow.append(label,elem('strong',formatEuro(s.totalCents)));
      checkoutReview.replaceChildren(lines,facts,totalRow);
      showLocation(document.querySelector('#order-location'),'idle');
    }
  }
  document.querySelector('#cart-checkout').addEventListener('click',()=>{
    if(!enabled||!windows.length)return;
    report(checkoutFeedback,'');cartDialog.close();step=2;drawStep();stepper.showModal();
  });
  orderNext.addEventListener('click',()=>{
    if(step===2&&!slotSelect.value){report(checkoutFeedback,'Scegli una fascia.',true);return;}
    if(step===2){report(checkoutFeedback,'');step=4;drawStep();}
  });
  orderBack.addEventListener('click',()=>{if(step===4){report(checkoutFeedback,'');step=2;drawStep();}});
  stepper.addEventListener('close',()=>{locationAbort?.abort();locationAbort=null;});
  orderSubmit.addEventListener('click',async()=>{
    if(!user||!cart.length||!slotSelect.value||!enabled)return;
    orderSubmit.disabled=true;orderBack.disabled=true;report(checkoutFeedback,'');
    const where=document.querySelector('#order-location');
    showLocation(where,'pending');
    const controller=new AbortController();locationAbort=controller;
    try {
      let loc;
      try{loc=await positionOnce(controller.signal);}
      catch(error){const key=error.name!=='AbortError'&&locationProblem(error);if(key){showLocation(where,key,{detail:error.message});return;}throw error;}
      if(!stepper.open)return;
      showLocation(where,'ok',{detail:'Invio della prenotazione…'});
      requestKey??=crypto.randomUUID();
      const {data,error}=await client.rpc('submit_promoted_order',{
        p_bar:context.barId,p_window:slotSelect.value,p_items:toRpcItems(cart),
        p_key:requestKey,p_latitude:loc.coords.latitude,p_code:coupon.value.trim(),
        p_longitude:loc.coords.longitude,p_accuracy:loc.coords.accuracy,
        p_observed:new Date(loc.timestamp).toISOString()
      });
      if(error){const key=locationProblem(error);if(key){showLocation(where,key);report(checkoutFeedback,'');return;}throw error;}
      if(!data)throw new Error('Conferma non ricevuta: controlla i tuoi ordini prima di riprovare.');
      changeCart([]);requestKey=null;coupon.value='';stepper.close();
      await loadOrders();location.hash='orders';
      report(feedback,'Prenotazione confermata. Mostra il QR al bar quando l’ordine è pronto.');
    } catch(err){if(err.name!=='AbortError'){showLocation(where,'idle');report(checkoutFeedback,err.message||'Ordine non riuscito.',true);}}
    finally{if(locationAbort===controller)locationAbort=null;orderSubmit.disabled=false;orderBack.disabled=false;}
  });
  async function loadOrders(){
    if(!user)return;
    void loadFavorites();
    report(feedback,'Caricamento ordini…');
    const {data,error}=await client.from('orders')
      .select('id,bar_id,school_id,display_no,pickup_token,status,payment_status,total_cents,created_at,pickup_windows(service_date,starts_at),order_items(product_id,product_name,quantity)')
      .eq('customer_id',user.id).order('created_at',{ascending:false}).limit(50);
    if(error){report(feedback,'Ordini non disponibili: '+error.message,true);return;}
    history.replaceChildren();
    const STEPS=[['confirmed','Confermato'],['preparing','Preparazione'],['ready','Pronto'],['delivered','Ritirato']];
    for(const o of data||[]){
      const box=elem('article','','order-card customer-order');
      box.dataset.status=o.status;
      const head=elem('header','','order-card-head');
      head.append(elem('h3',`Ordine #${o.display_no}`),badge(orderStatusLabel(o.status),orderStatusTone(o.status)));
      box.append(head);
      const position=STEPS.findIndex(([key])=>key===o.status);
      if(position>=0){
        const progress=elem('ol','','order-progress');progress.setAttribute('aria-label','Avanzamento dell’ordine');
        STEPS.forEach(([,label],index)=>{
          const li=elem('li',label);li.dataset.done=String(index<position||(index===position&&o.status==='delivered'));
          if(index===position&&o.status!=='delivered')li.setAttribute('aria-current','step');
          progress.append(li);
        });
        box.append(progress);
      }
      const pay=paymentState(o);
      const meta=elem('p','','order-meta');
      meta.append(elem('span','Ritiro '+slotLabel(o)),elem('strong',formatEuro(o.total_cents)),badge(pay.label,pay.tone));
      box.append(meta);
      const ul=elem('ul','','order-items');
      (o.order_items||[]).forEach(x=>{const li=elem('li');li.append(elem('b',x.quantity+'× '),document.createTextNode(x.product_name));ul.append(li);});
      box.append(ul);
      const primary=elem('div','','order-actions');
      const secondary=elem('div','','order-actions');
      const open=!['cancelled','delivered','no_show'].includes(o.status);
      if(open && o.pickup_token){
        const ticket=elem('button','Mostra QR di ritiro','button button-primary');
        ticket.type='button';
        ticket.addEventListener('click',()=>{
          window.dispatchEvent(new CustomEvent('breakapp:pickup-ticket',{
            detail:{pickupToken:o.pickup_token,displayNo:o.display_no}
          }));
        });
        primary.append(ticket);
      }
      if(open&&o.payment_status==='due'&&o.total_cents>0){
        const stripe=elem('button','Paga online','button button-outline');
        stripe.type='button';
        stripe.addEventListener('click',async()=>{
          if(!await confirmDialog({title:'Pagare online '+formatEuro(o.total_cents)+'?',
            message:'Si apre la pagina di pagamento Stripe. In questa versione di prova Stripe è in modalità test: non viene addebitato denaro reale.',
            confirmLabel:'Vai al pagamento'})){
            return;
          }
          stripe.disabled=true;
          const key=stripeAttemptKeys.get(o.id)||crypto.randomUUID();
          stripeAttemptKeys.set(o.id,key);
          try{
            const {data,error}=await client.functions.invoke('stripe-checkout-individual',{
              body:{order_id:o.id,request_key:key}
            });
            if(error)throw await paymentError(error);
            if(data?.error)throw new Error(data.error);
            if(!data?.checkout_url||
                !data.checkout_url.startsWith('https://checkout.stripe.com/')){
              throw new Error('URL Stripe non verificato: transazione interrotta');
            }
            window.location.assign(data.checkout_url);
          }catch(err){
            report(feedback,'Pagamento non avviato: '+friendlyError(err,'il pagamento online non è disponibile.'),true);
            stripe.disabled=false;
          }
        });
        primary.append(stripe);
      }
      const reorder=elem('button','Riordina','button button-outline button-small');reorder.type='button';
      reorder.addEventListener('click',()=>{
        if(context.barId!==o.bar_id)return report(feedback,'Seleziona prima nel menu il bar di questo ordine.',true);
        const next=(o.order_items||[]).map(i=>({product_id:i.product_id,quantity:i.quantity}));
        try{cartSummary(next,context.products);changeCart(next);location.hash='menu';renderCart();cartDialog.showModal();}catch(error){report(feedback,error.message,true);}
      });
      if(o.status==='confirmed'&&o.payment_status==='due'){
        const cancel=elem('button','Annulla ordine','button button-danger-outline button-small');
        cancel.type='button';
        cancel.addEventListener('click',async()=>{
          if(!await confirmDialog({title:'Annullare l’ordine #'+o.display_no+'?',message:'L’annullamento è definitivo.',confirmLabel:'Annulla ordine',cancelLabel:'Indietro',danger:true}))return;
          cancel.disabled=true;
          const result=await client.rpc('cancel_individual_order',{p_order_id:o.id});
          if(result.error){report(feedback,result.error.message,true);cancel.disabled=false;return;}
          await loadOrders();
        });secondary.append(cancel);
      }
      const help=elem('button','Richiedi assistenza','button button-ghost button-small');
      help.type='button';
      help.addEventListener('click',()=>{
        window.dispatchEvent(new CustomEvent('breakapp:support-order',{
          detail:{schoolId:o.school_id,orderId:o.id}
        }));
      });
      secondary.prepend(reorder);secondary.append(help);
      if(primary.childElementCount)box.append(primary);
      if(open){
        const more=elem('details','','order-more');more.append(elem('summary','Altre azioni'),secondary);box.append(more);
      }else box.append(secondary);
      history.append(box);
    }
    if(!history.childElementCount){
      const empty=elem('div','','empty-state');
      const link=elem('a','Apri il menu','button button-primary');link.href='#menu';
      empty.append(elem('strong','Nessun ordine'),elem('p','Le prenotazioni che fai dal menu compaiono qui, con il QR per il ritiro.'),link);
      history.append(empty);
    }
    const noticeArea=document.querySelector('#customer-service-notices');
    if(noticeArea){
      const n=await client.from('customer_notifications')
        .select('message,created_at,read_at')
        .eq('user_id',user.id).order('created_at',{ascending:false}).limit(15);
      noticeArea.replaceChildren();
      if(!n.error && n.data?.length){
        const h=elem('h3','Avvisi sui tuoi ordini');
        noticeArea.append(h);
        n.data.forEach(row=>{
          const card=elem('div','','service-notice');
          card.append(elem('strong',new Intl.DateTimeFormat('it-IT',{timeZone:'Europe/Rome',day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}).format(new Date(row.created_at))),
            elem('p',row.message));noticeArea.append(card);
        });
      }
    }
    if(feedback.dataset.type!=='error'&&/^Caricamento/.test(feedback.textContent))report(feedback,'');
  }
  function action(box,label,callback,{primary=false}={}){
    const button=elem('button',label,primary?'button button-primary':'button button-outline button-small');
    button.type='button';
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
    const generation=++staffFetchSequence,actor=user.id;
    const schools=staffContextSchool&&staffSchools.includes(staffContextSchool)
      ?[staffContextSchool]:[...staffSchools];
    // Never let newer closed orders push an older, still-open order out of the
    // Banco list. Query server-side by status and read multiple RLS-scoped pages.
    const active=['confirmed','preparing','ready'];
    const closed=['delivered','no_show','cancelled'];
    const visibility=staffVisibilityFilter.value;
    const groups=visibility==='active'?[active]:visibility==='closed'?[closed]:[active,closed];
    const orders=[],seen=new Set();
    let omitted=0;
    for(const statuses of groups){
      let total=null,loaded=0;
      for(let page=0;page<STAFF_MAX_PAGES;page++){
        const offset=page*STAFF_PAGE_SIZE;
        const {data,error,count}=await client.from('orders')
          .select(STAFF_FIELDS,{count:'exact'})
          .in('school_id',schools).in('status',statuses)
          .order('created_at',{ascending:false}).order('id',{ascending:false})
          .range(offset,offset+STAFF_PAGE_SIZE-1);
        if(generation!==staffFetchSequence||user?.id!==actor)return;
        if(error){
          report(staffFeedback,'Impossibile aggiornare il banco: '+error.message,true);
          return;
        }
        total=Number.isFinite(count)?count:total;
        for(const order of data||[]){
          if(seen.has(order.id))continue;
          seen.add(order.id);orders.push(order);
        }
        loaded+=data?.length||0;
        if(!data?.length||data.length<STAFF_PAGE_SIZE||total!==null&&loaded>=total)break;
      }
      if(total!==null && loaded<total)omitted+=total-loaded;
    }
    if(generation!==staffFetchSequence||user?.id!==actor)return;
    staffOrders=orders;
    updateSlotFilter();drawStaff();
    if(omitted>0)
      report(staffFeedback,'ATTENZIONE: '+omitted+
        ' ordini non sono ancora visibili in questo elenco. Non considerare completa la lista: consulta i report e avvisa l’Admin; riduci la fascia e aggiorna.',true);
    else{
      report(staffFeedback,'');
      staffLiveStatus.title='Ultimo aggiornamento alle '+new Intl.DateTimeFormat('it-IT',{hour:'2-digit',minute:'2-digit',second:'2-digit'}).format(new Date());
    }
    await loadCashRefunds();
  }
  async function loadCashRefunds(){
    const version=++cashRefundVersion;
    if(!user||!staffSchools.length){
      cashRefunds=[];drawCashRefunds();return;
    }
    const actor=user.id;
    const schools=staffContextSchool&&staffSchools.includes(staffContextSchool)
      ?[staffContextSchool]:staffSchools;
    const results=await Promise.all(schools.map(schoolId=>
      client.rpc('list_staff_pending_cash_refunds',{p_school:schoolId})
    ));
    if(version!==cashRefundVersion||user?.id!==actor)return;
    const failure=results.find(result=>result.error);
    if(failure){
      cashRefunds=[];drawCashRefunds();
      report(cashRefundFeedback,'Impossibile leggere le restituzioni: '+failure.error.message,true);
      return;
    }
    cashRefunds=results.flatMap(result=>Array.isArray(result.data?.items)?result.data.items:[])
      .filter(obligation=>obligation.status==='pending'&&staffSchools.includes(obligation.school_id));
    const remaining=results.reduce((n,r)=>n+Math.max(0,Number(r.data?.total||0)-200),0);
    if(results.some(r=>r.data?.has_more)){
      report(cashRefundFeedback,'Attenzione: '+remaining+
        ' restituzioni aggiuntive non sono visualizzate. Contatta l’Admin per la riconciliazione completa.',true);
    }else cashRefundFeedback.textContent='';
    drawCashRefunds();
  }
  function drawCashRefunds(){
    cashRefundList.replaceChildren();
    const panel=document.querySelector('#staff-cash-refunds-panel');
    if(!cashRefunds.length){
      cashRefundList.append(elem('p','Nessuna restituzione al banco da registrare.'));
      if(panel)panel.hidden=!cashRefundFeedback.textContent;
      return;
    }
    if(panel)panel.hidden=false;
    for(const obligation of cashRefunds){
      const order=staffOrders.find(x=>x.id===obligation.order_id);
      const title=order?'Ordine #'+order.display_no:
        obligation.group_order_id?'Ordine di gruppo':'Ordine concluso non presente negli ultimi 100';
      const box=elem('article','','order-card');
      box.append(
        elem('h4',title+' · '+formatEuro(obligation.amount_cents)),
        elem('p','Restituzione ancora da effettuare. Il sistema non può accreditare automaticamente contanti o pagamenti del POS esterno.'),
        elem('p','Motivo: '+(obligation.reason||'non specificato'))
      );
      const button=elem('button','Registra restituzione','button button-outline button-small');
      button.type='button';
      button.addEventListener('click',()=>{
        if(!user||!staffSchools.includes(obligation.school_id))return;
        selectedCashRefund=obligation;
        cashReturnForm.reset();
        cashReturnFeedback.textContent='';
        cashReturnSummary.textContent=title+' · '+formatEuro(obligation.amount_cents)+
          '. Conferma soltanto dopo aver restituito realmente il denaro e verificato la cassa.';
        cashReturnDialog.showModal();
        cashReturnReason.focus();
      });
      box.append(button);
      cashRefundList.append(box);
    }
  }
  function updateSlotFilter(){
    const previous=staffSlotFilter.value;
    const slots=availableSlots(staffOrders.filter(o=>!staffContextSchool||o.school_id===staffContextSchool));
    staffSlotFilter.replaceChildren(new Option('Tutte le fasce','all'),
      ...slots.map(s=>new Option(s.label,s.key)));
    staffSlotFilter.value=slots.some(s=>s.key===previous)?previous:'all';
  }
  function drawProduction(){
    staffProduction.replaceChildren();
    const scoped=staffOrders.filter(o=>!staffContextSchool||o.school_id===staffContextSchool);
    const totals=productionTotals(scoped,{slot:staffSlotFilter.value});
    const count=totals.reduce((sum,p)=>sum+p.quantity,0);
    staffProductionTotal.textContent=count+' '+(count===1?'pezzo':'pezzi');
    if(!totals.length){
      staffProduction.append(elem('p','Nessun prodotto in attesa di preparazione.','staff-empty'));
      return;
    }
    for(const item of totals){
      const row=elem('div','','staff-production-item');
      row.append(elem('strong',item.name),elem('span',String(item.quantity),'staff-production-count'));
      staffProduction.append(row);
    }
  }
  const laneTabs=document.querySelector('#staff-lane-tabs');
  // On phones the production summary starts collapsed above the queue.
  if(matchMedia('(max-width: 1279px)').matches)document.querySelector('#staff-production-panel')?.removeAttribute('open');
  let selectedLane='pending';
  function drawLaneTabs(stages){
    laneTabs.replaceChildren();
    const visible=stages.filter(stage=>staffVisibilityFilter.value==='all'||(staffVisibilityFilter.value==='closed')===(stage.key==='closed'));
    if(!visible.some(stage=>stage.key===selectedLane))selectedLane=visible[0]?.key||'pending';
    staffList.dataset.lane=selectedLane;
    laneTabs.hidden=visible.length<2;
    for(const stage of visible){
      const tab=elem('button','');tab.type='button';tab.setAttribute('role','tab');
      tab.id='staff-lane-tab-'+stage.key;
      tab.setAttribute('aria-selected',String(stage.key===selectedLane));
      tab.tabIndex=stage.key===selectedLane?0:-1;
      tab.append(document.createTextNode(stage.label),elem('span',String(stage.orders.length),'count-pill'));
      tab.addEventListener('click',()=>{selectedLane=stage.key;drawStaff();document.getElementById(tab.id)?.focus();});
      tab.addEventListener('keydown',event=>{
        if(!['ArrowLeft','ArrowRight'].includes(event.key))return;
        const index=visible.indexOf(stage)+(event.key==='ArrowRight'?1:-1);
        const next=visible[(index+visible.length)%visible.length];
        selectedLane=next.key;drawStaff();document.getElementById('staff-lane-tab-'+next.key)?.focus();
      });
      laneTabs.append(tab);
    }
  }
  function drawStaff(){
    staffList.replaceChildren();
    staffList.dataset.view=staffVisibilityFilter.value;
    drawProduction();
    const scoped=staffOrders.filter(o=>!staffContextSchool||o.school_id===staffContextSchool);
    const stages=boardOrders(scoped,{
      slot:staffSlotFilter.value,
      visibility:staffVisibilityFilter.value,
      search:document.querySelector('#staff-search').value.trim()
    });
    drawLaneTabs(stages);
    let shown=0;
    for(const stage of stages){
      if(staffVisibilityFilter.value==='active'&&stage.key==='closed')continue;
      if(staffVisibilityFilter.value==='closed'&&stage.key!=='closed')continue;
      const lane=elem('section','','staff-board-lane');
      lane.dataset.stage=stage.key;
      lane.setAttribute('aria-label',stage.label);
      lane.setAttribute('role','tabpanel');lane.setAttribute('aria-labelledby','staff-lane-tab-'+stage.key);
      const head=elem('div','','staff-lane-header');
      head.append(elem('h3',stage.label),elem('span',String(stage.orders.length),'staff-count'));
      lane.append(head);
      const list=elem('div','','staff-lane-orders');
      for(const o of stage.orders){
        shown++;
        const box=elem('article','','order-card staff-order-card');
        box.dataset.status=o.status;
        const pay=paymentState(o,{staff:true});
        box.dataset.payment=pay.tone;
        const top=elem('div','','ticket-head');
        top.append(elem('h4',`#${o.display_no}`,'ticket-no'),elem('span',slotLabel(o),'ticket-slot'));
        box.append(top);
        box.setAttribute('aria-label','Ordine '+o.display_no);
        const ul=elem('ul','','ticket-items');
        (o.order_items||[]).forEach(x=>{const li=elem('li');li.append(elem('b',x.quantity+'×'),document.createTextNode(' '+x.product_name));ul.append(li);});
        box.append(ul);
        const foot=elem('div','','ticket-foot');
        foot.append(elem('strong',formatEuro(o.total_cents),'ticket-total'),badge(pay.label,pay.tone));
        // Lanes already name the state; only the mixed "closed" lane repeats it.
        if(stage.key==='closed')foot.append(elem('span',orderStatusLabel(o.status),'staff-status staff-status--'+o.status));
        box.append(foot);
        const actions=elem('div','','order-actions');
        if(o.status==='confirmed'){
          action(actions,'Prepara',()=>client.rpc('advance_individual_order',{p_order_id:o.id,p_next:'preparing'}),{primary:true});
          action(actions,'Pronto',()=>client.rpc('advance_individual_order',{p_order_id:o.id,p_next:'ready'}));
        }
        if(o.status==='preparing')action(actions,'Pronto',()=>client.rpc('advance_individual_order',{p_order_id:o.id,p_next:'ready'}),{primary:true});
        if(o.status==='ready'&&o.payment_status==='due'){
          for(const [label,method] of [['Incassa contanti','cash'],['POS esterno','external_pos']]){
            action(actions,label,async()=>{
              const balance=await client.rpc('workflow_order_details',{p_kind:'individual',p_order:o.id});if(balance.error)return balance;
              if(!await decideStaffAction(`Hai incassato realmente ${formatEuro(balance.data.due_cents)} tramite ${label}? Conferma soltanto dopo aver verificato l'incasso.`))return null;
              return client.rpc('record_individual_counter_payment',{p_order_id:o.id,p_method:method,p_request_key:crypto.randomUUID()});
            },{primary:method==='cash'});
          }
        }
        if(o.status==='ready'&&o.payment_status==='paid'){
          action(actions,'Consegna',async()=>{
            if(!await decideStaffAction('Confermi di avere consegnato tutti i prodotti di questo ordine?'))return null;
            return client.rpc('advance_individual_order',{p_order_id:o.id,p_next:'delivered'});
          },{primary:true});
        }
        if(o.payment_status==='paid'&&['delivered','no_show'].includes(o.status)){
          const refund=elem('button','Rimborsa','button button-outline button-small');
          refund.type='button';
          refund.setAttribute('aria-label','Rimborsa ordine numero '+o.display_no);
          refund.addEventListener('click',()=>{
            if(!user||!staffSchools.includes(o.school_id))return;
            selectedRefund=o;
            refundForm.reset();
            refundFeedback.textContent='';
            refundSummary.textContent='Ordine #'+o.display_no+' · '+formatEuro(o.total_cents)+
              ' · '+(o.payment_method==='stripe'?'Pagamento online Stripe':o.payment_method==='external_pos'?'POS esterno':'Pagamento al banco')+
              '. Verrà rimborsato solo il credito residuo effettivamente incassato.';
            refundDialog.showModal();
            refundReason.focus();
          });
          actions.append(refund);
        }
        if(actions.childElementCount)box.append(actions);
        list.append(box);
      }
      if(!stage.orders.length)list.append(elem('p','Nessun ordine in questo stato.','staff-empty'));
      lane.append(list);staffList.append(lane);
    }
    if(!shown && !staffList.childElementCount)
      staffList.append(elem('p','Nessun ordine corrisponde ai filtri.','staff-empty'));
  }
  async function checkStaff(){
    const attempt=++staffAuthVersion,actor=user?.id;
    stopStaffFeed();
    staffFetchSequence++;
    staffSchools=[];staffPanel.hidden=true;
    cashRefundVersion++;cashRefunds=[];drawCashRefunds();
    if(!actor)return;
    const {data,error}=await client.from('school_memberships')
      .select('school_id,role_assignments(role_code)')
      .eq('user_id',actor).eq('membership_status','active');
    if(attempt!==staffAuthVersion||user?.id!==actor)return;
    if(error){
      report(staffFeedback,'Ruoli non verificabili: '+error.message,true);
      return;
    }
    const assurance=await client.auth.mfa.getAuthenticatorAssuranceLevel();
    if(attempt!==staffAuthVersion||user?.id!==actor)return;
    const adminVerified=!assurance.error&&assurance.data.currentLevel==='aal2';
    staffSchools=[...new Set((data||[]).filter(m=>
      (m.role_assignments||[]).some(r=>r.role_code==='bartender'||
        (r.role_code==='school_admin'&&adminVerified))
    ).map(m=>m.school_id))];
    staffPanel.hidden=!staffSchools.length;
    if(staffSchools.length){
      await fetchStaffOrders();
      if(attempt===staffAuthVersion&&user?.id===actor&&staffSchools.length)
        startStaffFeed();
    }else staffLiveStatus.textContent='Accesso staff non disponibile';
  }
  window.addEventListener('breakapp:workspace-context',event=>{
    const role=event.detail?.role||'customer';
    if(refundDialog.open)refundDialog.close();
    if(cashReturnDialog.open)cashReturnDialog.close();
    if(actionDialog.open)finishStaffDecision(false);
    if(role!=='customer'){
      if(productDialog.open)productDialog.close();
      if(cartDialog.open)cartDialog.close();
      if(stepper.open)stepper.close();
    }
    staffContextSchool=event.detail?.schoolId||null;
    if(user&&staffSchools.length){
      updateSlotFilter();drawStaff();
      startStaffFeed();
      queueStaffRefresh();
    }
  });
  document.querySelector('#orders-refresh').addEventListener('click',()=>void loadOrders());
  document.querySelector('#staff-refresh').addEventListener('click',()=>void checkStaff());
  document.querySelector('#staff-search').addEventListener('input',drawStaff);
  staffSlotFilter.addEventListener('change',drawStaff);
  staffVisibilityFilter.addEventListener('change',()=>{void fetchStaffOrders();});
  function setUser(next){
    const changed=user?.id!==next?.id;user=next;section.hidden=!user;
    if(!user){
      if(actionDialog.open)finishStaffDecision(false);
      if(productDialog.open)productDialog.close();
      if(cartDialog.open)cartDialog.close();
      if(stepper.open)stepper.close();
      stopStaffFeed();staffFetchSequence++;staffAuthVersion++;
      staffSchools=[];staffOrders=[];updateSlotFilter();drawStaff();
      if(refundDialog.open)refundDialog.close();
      if(cashReturnDialog.open)cashReturnDialog.close();
      cashRefundVersion++;cashRefunds=[];drawCashRefunds();
      version++;enabled=false;windows=[];requestKey=null;
      staffPanel.hidden=true;cart=[];showCartBar();return;
    }
    if(changed){
      stopStaffFeed();staffFetchSequence++;staffAuthVersion++;
      staffSchools=[];staffPanel.hidden=true;
      cart=[];showCartBar();void fetchWindows();void loadOrders();void checkStaff();
    }
  }
  client.auth.onAuthStateChange((_event,session)=>queueMicrotask(()=>setUser(session?.user||null)));
  client.auth.getUser().then(({data,error})=>{if(!error)setUser(data?.user||null);});
}
