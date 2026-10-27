const imageTypes=Object.freeze({'image/jpeg':'jpg','image/png':'png','image/webp':'webp'});
const fileMax=4194304;
const element=(tag,content='',cls='')=>{const node=document.createElement(tag);node.textContent=content;node.className=cls;return node;};

export function initializeSupportCenter(client) {
  if(!client)return;
  const panel=document.getElementById('support-center');
  const feedback=document.getElementById('support-feedback');
  const school=document.getElementById('support-school');
  const ordersSelect=document.getElementById('support-order-reference');
  const groupSelect=document.getElementById('support-group-reference'),groupOptions=document.getElementById('support-group-options'),
    groupVisibility=document.getElementById('support-group-visibility'),groupLine=document.getElementById('support-group-line'),groupPayment=document.getElementById('support-group-payment');
  const list=document.getElementById('support-ticket-list');
  const detail=document.getElementById('support-detail-panel');
  const title=document.getElementById('support-detail-title');
  const state=document.getElementById('support-detail-status');
  const thread=document.getElementById('support-thread');
  const createForm=document.getElementById('support-create-form');
  const replyForm=document.getElementById('support-reply-form');
  const reopenForm=document.getElementById('support-reopen-form');
  const adminActions=document.getElementById('support-admin-actions');
  const reopenList=document.getElementById('support-reopen-requests');
  let user=null,schools=[],orders=[],tickets=[],current=null,adminSchools=new Set();
  let createRequestKey=null,pendingOrder=null,pendingSchool=null,generation=0;
  let groupReferences=[];
  function groupFields(){
    const g=groupReferences.find(g=>g.id===groupSelect.value);groupOptions.hidden=!g;
    ordersSelect.disabled=school.disabled=Boolean(g);if(g){ordersSelect.value='';school.value=g.school_id;}
    groupLine.replaceChildren(new Option('Nessuno',''));groupPayment.replaceChildren(new Option('Nessuno',''));
    for(const i of g?.lines||[])groupLine.add(new Option(i.quantity+' × '+i.name,i.id));
    for(const p of g?.payments||[])groupPayment.add(new Option((p.amount_cents/100).toFixed(2)+' € · '+p.status,p.id));
    groupLine.disabled=groupPayment.disabled=groupVisibility.value!=='personal';
  }
  groupSelect.addEventListener('change',groupFields);groupVisibility.addEventListener('change',groupFields);

  const report=(message,error=false)=>{
    feedback.textContent=message;
    feedback.dataset.type=error?'error':'information';
  };
  function validateFile(file) {
    if(!file)return null;
    const ext=imageTypes[file.type];
    if(!ext || !file.size || file.size>fileMax)
      throw new Error('Allegato non valido: solo JPG, PNG o WebP, massimo 4 MB.');
    return ext;
  }
  function schoolName(id){return schools.find(s=>s.id===id)?.name||'Scuola';}
  function formatDate(value){return new Date(value).toLocaleString('it-IT');}

  async function uploadPhoto(file,ticket,messageId){
    if(!file)return;
    const ext=validateFile(file);
    const path=ticket.school_id+'/'+ticket.id+'/'+crypto.randomUUID()+'.'+ext;
    const bucket=client.storage.from('breakapp-ticket-images');
    const uploaded=await bucket.upload(path,file,{contentType:file.type,upsert:false,cacheControl:'60'});
    if(uploaded.error)throw uploaded.error;
    const saved=await client.from('support_attachments').insert({
      school_id:ticket.school_id,ticket_id:ticket.id,message_id:messageId,
      uploader_id:user.id,object_path:path,mime_type:file.type,size_bytes:file.size
    }).select('id').single();
    if(saved.error)throw new Error('Fotografia caricata, ma registrazione allegato fallita. Contatta l’assistenza: '+
      saved.error.message);
  }

  function fillSchools(){
    const old=school.value;
    school.replaceChildren();
    for(const s of schools)school.add(new Option(s.name,s.id));
    if(pendingSchool && schools.some(s=>s.id===pendingSchool))school.value=pendingSchool;
    else if(schools.some(s=>s.id===old))school.value=old;
    pendingSchool=null;
    fillOrderReferences();
  }
  function fillOrderReferences(){
    const old=ordersSelect.value;
    ordersSelect.replaceChildren(new Option('Nessun ordine specifico',''));
    for(const o of orders.filter(o=>o.school_id===school.value))
      ordersSelect.add(new Option('Ordine #'+o.display_no,o.id));
    if(pendingOrder&&orders.some(o=>o.id===pendingOrder&&o.school_id===school.value)){
      ordersSelect.value=pendingOrder;pendingOrder=null;
    }else if([...ordersSelect.options].some(o=>o.value===old))ordersSelect.value=old;
  }
  function renderTickets(){
    list.replaceChildren();
    if(!tickets.length){list.append(element('p','Non ci sono ancora ticket.'));return;}
    for(const t of tickets){
      const card=element('article','','support-ticket-card');
      card.append(element('strong',t.subject),element('span',schoolName(t.school_id)+' · '+t.status),
        element('small','Aggiornato '+formatDate(t.updated_at)));
      const open=element('button','Apri conversazione','button button-outline button-small');
      open.type='button';open.addEventListener('click',()=>void openTicket(t.id));
      card.append(open);list.append(card);
    }
  }
  async function readTicketList(){
    if(!user)return;
    const seq=++generation;
    report('Caricamento ticket da Supabase…');
    const {data,error}=await client.from('support_tickets')
      .select('id,school_id,order_id,group_id,visibility,owner_id,subject,category,status,created_at,updated_at')
      .order('updated_at',{ascending:false}).limit(100);
    if(seq!==generation)return;
    if(error){report(error.message,true);return;}
    tickets=data||[];renderTickets();
    report('Richieste aggiornate: '+tickets.length+'.');
  }
  async function renderAttachments(messageId,allAttachments) {
    const data=allAttachments.filter(item=>item.message_id===messageId);
    if(!data.length)return null;
    const links=element('div','','support-attachments');
    for(const photo of data) {
      const {data:signed,error:err}=await client.storage.from('breakapp-ticket-images')
        .createSignedUrl(photo.object_path,120);
      if(err || !signed?.signedUrl)continue;
      const a=element('a','Visualizza fotografia','text-link');
      a.href=signed.signedUrl;a.target='_blank';a.rel='noopener noreferrer';
      links.append(a);
    }
    return links;
  }
  async function openTicket(id){
    if(!user)return;
    const seq=++generation;
    report('Lettura della conversazione protetta…');
    const {data:t,error}=await client.from('support_tickets')
      .select('id,school_id,order_id,group_id,visibility,owner_id,subject,status,category,created_at')
      .eq('id',id).single();
    if(seq!==generation)return;
    if(error){report(error.message,true);return;}
    current=t;detail.hidden=false;
    title.textContent=t.subject;
    state.textContent='Stato: '+t.status+' · '+schoolName(t.school_id)+
      (t.order_id?' · Ticket collegato a un ordine':'');
    const admin=adminSchools.has(t.school_id);
    adminActions.hidden=!admin;
    document.getElementById('support-admin-state').value=t.status;
    const isClosed=['resolved','closed'].includes(t.status);
    replyForm.hidden=isClosed;reopenForm.hidden=!isClosed||(t.owner_id!==user.id&&t.visibility!=='group');
    const [messages,reopen]=await Promise.all([
      client.from('support_messages').select('id,author_id,body,created_at')
        .eq('ticket_id',id).order('created_at').limit(150),
      client.from('support_reopen_requests')
        .select('id,reason,status,requested_at').eq('ticket_id',id)
        .order('requested_at',{ascending:false}).limit(20)
    ]);
    if(seq!==generation)return;
    if(messages.error){report(messages.error.message,true);return;}
    thread.replaceChildren();
    const messageIds=(messages.data||[]).map(m=>m.id);
    const attachments=messageIds.length
      ?await client.from('support_attachments')
        .select('id,message_id,object_path,mime_type').in('message_id',messageIds)
      :{data:[],error:null};
    if(seq!==generation)return;
    if(attachments.error){report(attachments.error.message,true);return;}
    for(const message of messages.data||[]){
      const article=element('article','','support-message');
      article.append(
        element('strong',message.author_id===user.id?'Tu':t.visibility==='group'?'Membro del gruppo o personale':'Interlocutore'),
        element('time',formatDate(message.created_at)),
        element('p',message.body)
      );
      thread.append(article);
      const links=await renderAttachments(message.id,attachments.data||[]);
      if(seq!==generation)return;
      if(links)article.append(links);
    }
    reopenList.replaceChildren();
    if(admin) {
      for(const request of reopen.data||[]){
        const row=element('div','','service-list-item');
        row.append(element('strong','Riapertura '+request.status),
          element('p',request.reason));
        if(request.status==='pending'){
          for(const [label,approve] of [['Approva',true],['Rifiuta',false]]){
            const button=element('button',label,'button button-outline button-small');
            button.type='button';
            button.addEventListener('click',async()=>{
              if(!confirm((approve?'Approvare':'Rifiutare')+' la riapertura?'))return;
              button.disabled=true;
              const {error:err}=await client.rpc('review_support_reopen',{
                p_request_id:request.id,p_approve:approve,p_reason:''
              });
              if(err){report(err.message,true);button.disabled=false;return;}
              await openTicket(id);await readTicketList();
            });
            row.append(button);
          }
        }
        reopenList.append(row);
      }
    }
    if(!thread.childElementCount)thread.append(element('p','Nessun messaggio.'));
    report('Conversazione aggiornata.');
  }
  async function initialData(){
    if(!user)return;
    const seq=++generation;
    const [s,o,m,a,g]=await Promise.all([
      client.from('schools').select('id,name').eq('is_active',true).order('name'),
      client.from('orders').select('id,school_id,display_no')
        .eq('customer_id',user.id).order('created_at',{ascending:false}).limit(100),
      client.from('school_memberships').select('school_id,role_assignments(role_code)')
        .eq('user_id',user.id).eq('membership_status','active'),
      client.auth.mfa.getAuthenticatorAssuranceLevel(),client.rpc('my_support_group_references')
    ]);
    if(seq!==generation)return;
    if(s.error||o.error||m.error||a.error||g.error){
      report((s.error||o.error||m.error||a.error||g.error).message,true);return;
    }
    schools=s.data||[];orders=o.data||[];
    groupReferences=g.data||[];groupSelect.replaceChildren(new Option('Nessun gruppo',''));
    for(const row of groupReferences)groupSelect.add(new Option(row.title,row.id));groupFields();
    const aal2=a.data.currentLevel==='aal2';
    adminSchools=new Set((m.data||[]).filter(x=>aal2 &&
      (x.role_assignments||[]).some(r=>r.role_code==='school_admin'))
      .map(x=>x.school_id));
    fillSchools();await readTicketList();
  }
  createForm.addEventListener('input',()=>{if(!createRequestKey)createRequestKey=crypto.randomUUID();});
  createForm.addEventListener('submit',async event=>{
    event.preventDefault();if(!user||!createForm.reportValidity())return;
    const btn=document.getElementById('support-create-button');
    const file=document.getElementById('support-create-file').files[0]||null;
    try{validateFile(file);}catch(err){report(err.message,true);return;}
    btn.disabled=true;
    createRequestKey ||= crypto.randomUUID();
    report('Creazione richiesta e messaggio su Supabase…');
    const shared=groupSelect.value;
    const {data:id,error}=await client.rpc(shared?'open_group_support_ticket':'open_support_ticket',shared?{
      p_group:shared,p_visibility:groupVisibility.value,p_line:groupVisibility.value==='personal'?groupLine.value||null:null,
      p_payment:groupVisibility.value==='personal'?groupPayment.value||null:null,
      p_subject:document.getElementById('support-subject').value.trim(),p_message:document.getElementById('support-message').value.trim(),p_key:createRequestKey
    }:{
      p_school_id:school.value,
      p_order_id:ordersSelect.value||null,p_order_item_id:null,
      p_category:document.getElementById('support-category').value,
      p_subject:document.getElementById('support-subject').value.trim(),
      p_message:document.getElementById('support-message').value.trim(),
      p_request_key:createRequestKey
    });
    if(error){report(error.message,true);btn.disabled=false;return;}
    const selectedSchool=school.value;
    const t={id,school_id:selectedSchool};
    try{
      if(file){
        const message=await client.from('support_messages')
          .select('id').eq('ticket_id',id).eq('author_id',user.id)
          .order('created_at').limit(1).single();
        if(message.error)throw message.error;
        await uploadPhoto(file,t,message.data.id);
      }
      createForm.reset();groupFields();createRequestKey=null;
      await readTicketList();await openTicket(id);
      report('Ticket creato. La conversazione è accessibile dal Centro assistenza.');
    }catch(err){
      createRequestKey=null;
      await readTicketList();await openTicket(id);
      report('Ticket creato, ma allegato non completato: '+err.message,true);
    }finally{btn.disabled=false;}
  });
  replyForm.addEventListener('submit',async event=>{
    event.preventDefault();if(!current||!replyForm.reportValidity())return;
    const btn=document.getElementById('support-reply-button');
    const file=document.getElementById('support-reply-file').files[0]||null;
    try{validateFile(file);}catch(err){report(err.message,true);return;}
    btn.disabled=true;
    const ticket={...current};
    const {data:messageId,error}=await client.rpc('post_support_message',{
      p_ticket_id:ticket.id,p_body:document.getElementById('support-reply-body').value.trim()
    });
    if(error){report(error.message,true);btn.disabled=false;return;}
    try{
      if(file)await uploadPhoto(file,ticket,messageId);
      replyForm.reset();
      await openTicket(ticket.id);await readTicketList();
    }catch(err){
      await openTicket(ticket.id);
      report('Messaggio inviato, ma allegato non completato: '+err.message,true);
    }finally{btn.disabled=false;}
  });
  reopenForm.addEventListener('submit',async event=>{
    event.preventDefault();if(!current||!reopenForm.reportValidity())return;
    const t=current;
    const {error}=await client.rpc('request_support_reopen',{
      p_ticket_id:t.id,p_reason:document.getElementById('support-reopen-reason').value.trim()
    });
    if(error){report(error.message,true);return;}
    reopenForm.reset();await openTicket(t.id);
    report('Richiesta di riapertura inviata. L’Admin valuterà la motivazione.');
  });
  document.getElementById('support-admin-save').addEventListener('click',async()=>{
    if(!current||!adminSchools.has(current.school_id))return;
    const t=current,selected=document.getElementById('support-admin-state').value;
    if(!confirm('Confermi il nuovo stato del ticket: '+selected+'?'))return;
    const {error}=await client.rpc('set_support_ticket_status',{
      p_ticket_id:t.id,p_status:selected,p_reason:''
    });
    if(error){report(error.message,true);return;}
    await openTicket(t.id);await readTicketList();
  });
  school.addEventListener('change',()=>{pendingOrder=null;pendingSchool=null;fillOrderReferences();});
  document.getElementById('support-refresh').addEventListener('click',()=>void initialData());
  window.addEventListener('breakapp:support-order',event=>{
    if(!user)return;
    const {schoolId,orderId}=event.detail||{};
    pendingSchool=schoolId;
    if(schools.some(s=>s.id===schoolId))school.value=schoolId;
    pendingOrder=orderId;fillOrderReferences();
    document.getElementById('support-category').value='order';
    location.hash='support-center';
    document.getElementById('support-subject').focus();
  });
  function loggedIn(next){
    const changed=user?.id!==next?.id;
    user=next;panel.hidden=!user;
    if(!user) {
      generation++;current=null;tickets=[];schools=[];orders=[];adminSchools.clear();
      list.replaceChildren();thread.replaceChildren();detail.hidden=true;return;
    }
    if(changed)void initialData();
  }
  client.auth.onAuthStateChange((_event,session)=>queueMicrotask(()=>loggedIn(session?.user||null)));
  client.auth.getUser().then(({data,error})=>{if(!error)loggedIn(data?.user||null);});
}
