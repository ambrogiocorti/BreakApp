const byId=id=>document.getElementById(id);
const make=(tag,text='',cls='')=>{const e=document.createElement(tag);e.textContent=text;e.className=cls;return e;};
export function initializeInAppNotifications(client){
 if(!client)return;
 const toggle=byId('notifications-toggle'),dialog=byId('notifications-dialog'),
 count=byId('notifications-unread'),list=byId('notifications-list'),
 feedback=byId('notifications-feedback'),permission=byId('notifications-permission');
 let user=null,channel=null,poll=null,epoch=0;
 const report=(value,error=false)=>{feedback.textContent=value;feedback.dataset.type=error?'error':'information';};
 async function foregroundNotice(notification){
   // This is foreground/browser-open only; no claims of closed-browser Web Push.
   if(!('Notification' in window)||Notification.permission!=='granted')return;
   try{
     const registration=await navigator.serviceWorker?.ready;
     if(registration?.showNotification){
       await registration.showNotification('BreakApp · nuovo avviso',{
         body:notification.message,tag:'breakapp-'+notification.id,
         data:{url:location.href},icon:`${import.meta.env.BASE_URL}icon-placeholder.svg`
       });
     }else {
       new Notification('BreakApp · nuovo avviso',{body:notification.message,
         tag:'breakapp-'+notification.id});
     }
   }catch{/* The in-app alert remains the authoritative fallback. */}
 }
 function renderRows(rows){
   list.replaceChildren();
   const unread=rows.filter(row=>!row.read_at).length;
   count.hidden=!unread;count.textContent=unread>99?'99+':String(unread);
   toggle.setAttribute('aria-label',unread
     ?'Notifiche: '+unread+' non lette':'Apri notifiche');
   if(!rows.length){list.append(make('p','Non ci sono notifiche.'));return;}
   for(const n of rows){
     const item=make('article','','notice-row'+(n.read_at?'':' notice-unread'));
     item.append(make('strong',new Date(n.created_at).toLocaleString('it-IT')),
       make('p',n.message));
     if(!n.read_at){
       const button=make('button','Segna come letta','button button-outline button-small');
       button.type='button';
       button.addEventListener('click',async()=>{
         button.disabled=true;
         const {error}=await client.from('customer_notifications')
           .update({read_at:new Date().toISOString()})
           .eq('id',n.id).eq('user_id',user.id);
         if(error){report(error.message,true);button.disabled=false;return;}
         await load();
       });
       item.append(button);
     }
     if(n.group_id){
       const link=make('a','Apri gruppi','text-link');link.href='#groups';item.append(link);
     }else if(n.ticket_id){
       const link=make('a','Centro assistenza','text-link');link.href='#support-center';item.append(link);
     }else if(n.order_id){
       const link=make('a','I miei ordini','text-link');link.href='#orders';item.append(link);
     }
     list.append(item);
   }
 }
 async function load(){
   if(!user)return;
   const current=++epoch,uid=user.id;
   const {data,error}=await client.from('customer_notifications')
     .select('id,message,created_at,read_at,group_id,ticket_id,order_id')
     .eq('user_id',uid).order('created_at',{ascending:false}).limit(100);
   if(current!==epoch||user?.id!==uid)return;
   if(error){report('Impossibile aggiornare gli avvisi: '+error.message,true);return;}
   renderRows(data||[]);
   report('Avvisi aggiornati.');
 }
 function stop(){
   epoch++;
   if(channel){void client.removeChannel(channel);channel=null;}
   if(poll){clearInterval(poll);poll=null;}
   list.replaceChildren();count.hidden=true;toggle.hidden=true;
   if(dialog.open)dialog.close();
 }
 function session(next){
   if(user?.id===next?.id)return;
   stop();
   user=next;
   if(!user)return;
   toggle.hidden=false;
   void load();
   // RLS restricts row delivery to the owner. Polling is fallback for
   // restrictive networks/browser suspensions or unconfigured Realtime.
   channel=client.channel('breakapp-notices-'+user.id);
   channel.on('postgres_changes',{event:'INSERT',schema:'public',
     table:'customer_notifications',filter:'user_id=eq.'+user.id},payload=>{
       if(!user||payload.new.user_id!==user.id)return;
       void foregroundNotice(payload.new);
       void load();
     }).on('postgres_changes',{event:'UPDATE',schema:'public',
      table:'customer_notifications',filter:'user_id=eq.'+user.id},()=>void load())
     .subscribe();
   poll=setInterval(()=>{if(document.visibilityState==='visible')void load();},60000);
 }
 toggle.addEventListener('click',()=>{
   if(!user)return;
   if(!dialog.open)dialog.showModal();
   void load();
 });
 byId('notifications-close').addEventListener('click',()=>dialog.close());
 byId('notifications-refresh').addEventListener('click',()=>void load());
 permission.addEventListener('click',async()=>{
   if(!('Notification' in window)){report('Il browser non supporta le notifiche di sistema.',true);return;}
   if(!window.isSecureContext){report('Le notifiche richiedono HTTPS.',true);return;}
   const status=await Notification.requestPermission();
   report(status==='granted'
    ?'Avvisi del browser attivi mentre BreakApp è aperta. Le push ad app chiusa richiedono ancora il dispatcher VAPID.'
    :'Permesso notifiche non concesso: gli avvisi in-app rimangono disponibili.',status!=='granted');
 });
 document.addEventListener('visibilitychange',()=>{
   if(document.visibilityState==='visible'&&user)void load();
 });
 client.auth.onAuthStateChange((_e,s)=>queueMicrotask(()=>session(s?.user||null)));
 client.auth.getUser().then(({data,error})=>{if(!error)session(data?.user||null);});
}
