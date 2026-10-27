import { formatEuro } from '../catalog/utils.js';
import { makePickupQrValue, parsePickupQrValue, parseOrderDisplayNumber } from './qr-utils.js';

const el=(tag,text,cls='')=>{
  const node=document.createElement(tag);
  node.textContent=text;node.className=cls;return node;
};
export function initializePickupQr(client) {
  if(!client)return;
  const ticket=document.querySelector('#customer-qr-dialog');
  const ticketCode=document.querySelector('#customer-qr-code');
  const ticketMeta=document.querySelector('#customer-qr-meta');
  const scanDialog=document.querySelector('#staff-scan-dialog');
  const cameraBtn=document.querySelector('#staff-start-camera');
  const video=document.querySelector('#staff-camera-video');
  const manual=document.querySelector('#staff-number-form');
  const manualInput=document.querySelector('#staff-number-input');
  const status=document.querySelector('#staff-scan-status');
  const result=document.querySelector('#staff-scan-result');
  let stream=null,frameId=null,active=false,inFlight=false;
  let queryVersion=0,currentUser=null;

  function report(message,error=false) {
    status.textContent=message;status.dataset.type=error?'error':'information';
  }
  window.addEventListener('breakapp:pickup-ticket',event=>{
    if(!currentUser)return;
    const {pickupToken,displayNo}=event.detail||{};
    ticketCode.replaceChildren();
    try{
      const value=makePickupQrValue(pickupToken);
      if(typeof window.QRCode!=='function')throw new Error('Generatore QR non disponibile.');
      new window.QRCode(ticketCode,{
        text:value,width:225,height:225,colorDark:'#080f21',colorLight:'#ffffff',
        correctLevel:window.QRCode.CorrectLevel.M
      });
      ticketMeta.textContent='Ordine #'+displayNo;
      ticket.showModal();
    }catch(err){
      ticketMeta.textContent='Impossibile generare il QR: '+err.message
        +'. Puoi comunicare al barista il numero ordine #'+displayNo+'.';
      ticket.showModal();
    }
  });

  function stopCamera(){
    active=false;
    if(frameId!==null){cancelAnimationFrame(frameId);frameId=null;}
    if(stream){stream.getTracks().forEach(track=>track.stop());stream=null;}
    video.pause();video.srcObject=null;video.hidden=true;inFlight=false;
    cameraBtn.disabled=false;cameraBtn.textContent='Apri fotocamera';
  }
  scanDialog.addEventListener('close',()=>{stopCamera();queryVersion+=1;});

  async function allowedStaff(schoolId) {
    if(!currentUser)return false;
    const [memberships,assurance]=await Promise.all([
      client.from('school_memberships')
        .select('school_id,role_assignments(role_code)')
        .eq('user_id',currentUser.id).eq('membership_status','active'),
      client.auth.mfa.getAuthenticatorAssuranceLevel()
    ]);
    if(memberships.error)return false;
    const aal2=!assurance.error && assurance.data.currentLevel==='aal2';
    return (memberships.data||[]).some(m=>m.school_id===schoolId&&
      (m.role_assignments||[]).some(r=>r.role_code==='bartender'
        ||(r.role_code==='school_admin'&&aal2)));
  }
  async function lookup(filter) {
    const version=++queryVersion;
    result.replaceChildren();report('Verifica ordine in corso...');
    try{
      let q=client.from('orders').select(
        'id,school_id,display_no,status,payment_status,total_cents,pickup_windows(service_date,starts_at,ends_at),order_items(product_name,quantity)'
      );
      q=filter.token?q.eq('pickup_token',filter.token):q.eq('display_no',filter.displayNo);
      const {data,error}=await q.maybeSingle();
      if(version!==queryVersion || !scanDialog.open)return;
      if(error)throw error;
      if(!data)throw new Error('Ordine non trovato oppure non autorizzato.');
      if(!await allowedStaff(data.school_id))throw new Error('Non sei autorizzato a gestire questo ordine.');
      if(version!==queryVersion || !scanDialog.open)return;
      drawOrder(data);
      report('Ordine #'+data.display_no+' verificato dal server.');
    }catch(err){if(version===queryVersion)report(err.message||'Ricerca ordine non riuscita.',true);}
  }

  function drawOrder(order) {
    result.replaceChildren();
    const heading=el('h3','Ordine #'+order.display_no+' · '+order.status);
    const slot=order.pickup_windows;
    const when=el('p',slot?'Ritiro: '+slot.service_date+' · '+slot.starts_at.slice(0,5):'Ritiro da verificare','catalog-help');
    const payment=el('p',
      'Totale: '+formatEuro(order.total_cents)+' · '+
      (order.payment_status==='paid'?'Pagato':'Saldo da incassare'),'catalog-help');
    const items=el('ul','', 'scan-item-list');
    for(const x of order.order_items||[]) items.append(el('li',x.quantity+' × '+x.product_name));
    result.append(heading,when,payment,items);
    if(order.status!=='ready'){
      result.append(el('p','Consegna non disponibile: ordine non pronto oppure già concluso.','catalog-help'));
      return;
    }
    const actions=el('div','', 'order-actions');
    async function execute(label,query){
      if(!confirm(label))return;
      const buttons=[...actions.querySelectorAll('button')];
      buttons.forEach(button=>{button.disabled=true;});
      report('Registrazione dell’operazione sul server…');
      try{
        const {error}=await query();
        if(error)throw error;
        await lookup({displayNo:String(order.display_no)});
        document.querySelector('#staff-refresh')?.click();
      }catch(err){
        report(err.message||'Operazione non riuscita.',true);
        buttons.forEach(button=>{button.disabled=false;});
      }
    }
    function command(label,message,callback){
      const button=el('button',label,'button button-primary button-small');
      button.type='button';button.addEventListener('click',()=>void execute(message,callback));
      actions.append(button);
    }
    if(order.payment_status==='due') {
      command('Incassa contanti',
        'Confermi di avere realmente ricevuto '+formatEuro(order.total_cents)+' in contanti?',
        ()=>client.rpc('record_individual_counter_payment',{
          p_order_id:order.id,p_method:'cash',p_request_key:crypto.randomUUID()
        }));
      command('POS esterno',
        'Confermi che il POS esterno ha già registrato correttamente il pagamento di '+formatEuro(order.total_cents)+'?',
        ()=>client.rpc('record_individual_counter_payment',{
          p_order_id:order.id,p_method:'external_pos',p_request_key:crypto.randomUUID()
        }));
    }
    if(order.payment_status==='paid'){
      command('Consegna ordine',
        'Confermi esplicitamente la consegna di tutti i prodotti al cliente?',
        ()=>client.rpc('advance_individual_order',{p_order_id:order.id,p_next:'delivered'}));
    }
    result.append(actions);
  }

  async function startCamera(){
    if(active||inFlight)return;
    cameraBtn.disabled=true;
    report('Verifica disponibilità scanner QR…');
    try{
      if(!('BarcodeDetector' in window) || !navigator.mediaDevices?.getUserMedia)
        throw new Error('Scanner fotografico non disponibile in questo browser. Usa la ricerca per numero.');
      const available=await window.BarcodeDetector.getSupportedFormats();
      if(!available.includes('qr_code'))
        throw new Error('Il browser non supporta la lettura QR. Usa il numero ordine.');
      const detector=new window.BarcodeDetector({formats:['qr_code']});
      stream=await navigator.mediaDevices.getUserMedia({
        video:{facingMode:{ideal:'environment'}},audio:false
      });
      video.srcObject=stream;video.hidden=false;
      await video.play();
      active=true;cameraBtn.textContent='Fotocamera attiva';
      report('Inquadra il QR personale del cliente.');
      const read=async()=>{
        if(!active||inFlight||!scanDialog.open)return;
        try{
          const codes=await detector.detect(video);
          if(!active||!scanDialog.open)return;
          for(const code of codes){
            const groupMatch=/^breakapp:group:([0-9a-f-]{36})$/i.exec(String(code.rawValue));
            if(groupMatch){
              stopCamera();scanDialog.close();
              window.dispatchEvent(new CustomEvent('breakapp:group-pickup-scanned',{
                detail:{token:groupMatch[1]}
              }));
              return;
            }
            const token=parsePickupQrValue(code.rawValue);
            if(token){
              stopCamera();
              await lookup({token});
              return;
            }
          }
        }catch(err){report('Lettura non riuscita. Riprova oppure cerca il numero ordine.',true);}
        if(active)frameId=requestAnimationFrame(()=>void read());
      };
      frameId=requestAnimationFrame(()=>void read());
    }catch(err){
      stopCamera();
      report(err.message||'Non è stato possibile aprire la fotocamera.',true);
    }finally{cameraBtn.disabled=false;}
  }
  window.addEventListener('breakapp:workspace-context',()=>{
    // Role/school switches invalidate a visible scanner and release its camera.
    if(scanDialog.open)scanDialog.close();
    stopCamera();
  });
  cameraBtn.addEventListener('click',()=>void startCamera());
  manual.addEventListener('submit',event=>{
    event.preventDefault();
    const displayNo=parseOrderDisplayNumber(manualInput.value);
    if(!displayNo)return report('Inserisci un numero d’ordine valido.',true);
    stopCamera();void lookup({displayNo});
  });
  document.querySelector('#staff-scan-open').addEventListener('click',()=>{
    if(!currentUser)return;
    result.replaceChildren();
    manual.reset();
    report('Scegli scansione QR oppure ricerca manuale.');
    scanDialog.showModal();
  });
  client.auth.onAuthStateChange((_event,session)=>queueMicrotask(()=>{
    currentUser=session?.user||null;
    if(!currentUser){stopCamera();if(scanDialog.open)scanDialog.close();if(ticket.open)ticket.close();}
  }));
  client.auth.getUser().then(({data,error})=>{
    if(!error)currentUser=data?.user||null;
  });
}
