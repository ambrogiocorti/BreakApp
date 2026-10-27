const byId=id=>document.getElementById(id);
// Revoke browser endpoint when signing out of a shared school device.
// Always unsubscribe locally, even when the remote deletion fails.
export async function revokeDevicePush(client){
 if(!('serviceWorker' in navigator))return;
 const registration=await navigator.serviceWorker.getRegistration();
 const subscription=await registration?.pushManager?.getSubscription();
 if(!subscription)return;
 let serverError=null;
 try {
  const {error}=await client.rpc('disable_my_push_subscription',{
   p_endpoint:subscription.endpoint
  });
  serverError=error;
 }catch(error){serverError=error;}
 const removed=await subscription.unsubscribe();
 if(!removed||serverError)
  throw new Error('La disattivazione delle notifiche non è stata verificata. Controlla i permessi del browser.');
}

const make=(tag,text='',cls='')=>{const e=document.createElement(tag);e.textContent=text;e.className=cls;return e;};
export function initializeInAppNotifications(client){
 if(!client)return;
 const toggle=byId('notifications-toggle'),dialog=byId('notifications-dialog'),
 count=byId('notifications-unread'),list=byId('notifications-list'),
 feedback=byId('notifications-feedback'),permission=byId('notifications-permission');
 let user=null,channel=null,poll=null,epoch=0,preferences=null,preferencesEpoch=0;
 const preferenceFields=['browser_alerts','push_orders','push_groups','push_support','push_announcements'];
 const preferenceInput=key=>byId('notice-'+key.replaceAll('_','-'));
 const report=(value,error=false)=>{feedback.textContent=value;feedback.dataset.type=error?'error':'information';};
 async function foregroundNotice(notification){
   // This is foreground/browser-open only; no claims of closed-browser Web Push.
   if(!preferences?.browser_alerts||!('Notification' in window)||Notification.permission!=='granted')return;
   try{
     const registration=await navigator.serviceWorker?.ready;
     if(registration?.showNotification){
       await registration.showNotification('BreakApp · nuovo avviso',{
         body:'Hai un nuovo avviso in BreakApp.',tag:'breakapp-'+notification.id,
         data:{url:location.href},icon:`${import.meta.env.BASE_URL}icon-placeholder.svg`
       });
     }else {
       new Notification('BreakApp · nuovo avviso',{body:'Hai un nuovo avviso in BreakApp.',
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
 async function loadPreferences(){
   if(!user)return;
   const current=++preferencesEpoch,uid=user.id;
   const {data,error}=await client.rpc('get_my_notification_preferences');
   if(current!==preferencesEpoch||user?.id!==uid)return;
   if(error){preferences=null;report('Preferenze non disponibili: '+error.message,true);return;}
   preferences=data;
   for(const key of preferenceFields)preferenceInput(key).checked=data?.[key]===true;
 }
 function stop(){
   epoch++;
   preferencesEpoch++;preferences=null;
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
   void loadPreferences();
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

 function vapidBytes(value){
   const normalized=value.replace(/-/g,'+').replace(/_/g,'/');
   const data=atob(normalized.padEnd(Math.ceil(normalized.length/4)*4,'='));
   return Uint8Array.from(data,ch=>ch.charCodeAt(0));
 }
 async function subscribeBackground(){
   if(!user)throw new Error('Accedi prima di attivare le push.');
   const uid=user.id;
   if(!window.isSecureContext||!('Notification' in window)||
      !('PushManager' in window)||!('serviceWorker' in navigator))
     throw new Error('Questo dispositivo/browser non supporta le Web Push.');
   const keyResponse=await fetch(client.supabaseUrl+'/functions/v1/push-public-key');
   const keyData=await keyResponse.json();
   if(!keyResponse.ok||!keyData.public_key)
     throw new Error('Push non configurate sul server. Servono le chiavi VAPID.');
   const grant=await Notification.requestPermission();
   if(grant!=='granted')throw new Error('Permesso push non concesso.');
   const sw=await navigator.serviceWorker.ready;
   let subscription=await sw.pushManager.getSubscription();
   if(!subscription){
     subscription=await sw.pushManager.subscribe({
       userVisibleOnly:true,applicationServerKey:vapidBytes(keyData.public_key)
     });
   }
   const publicData=subscription.toJSON();
   if(user?.id!==uid){await subscription.unsubscribe();throw new Error('Account cambiato: ripeti l’attivazione.');}
   if(!publicData.endpoint||!publicData.keys?.p256dh||!publicData.keys?.auth)
     throw new Error('Dati sottoscrizione Web Push incompleti.');
   // An endpoint must never remain registered under two different accounts
   // on a shared device: the RPC transfers ownership and expires stale jobs.
   const {error}=await client.rpc('register_my_push_subscription',{
     p_endpoint:publicData.endpoint,p_p256dh:publicData.keys.p256dh,
     p_auth_key:publicData.keys.auth
   });
   if(error)throw error;
   return 'Push registrate per questo dispositivo. La consegna richiede il dispatcher server attivo.';
 }

 byId('notification-preferences-form').addEventListener('submit',async event=>{
   event.preventDefault();if(!user)return;
   const uid=user.id,current=++preferencesEpoch;
   const button=event.currentTarget.querySelector('button[type="submit"]');button.disabled=true;
   const args=Object.fromEntries(preferenceFields.map(key=>['p_'+key,preferenceInput(key).checked]));
   try{
     const {data,error}=await client.rpc('set_my_notification_preferences',args);
     if(user?.id!==uid||current!==preferencesEpoch)return;
     if(error)throw error;
     preferences=data;report('Preferenze salvate. Gli invii già affidati al browser possono ancora arrivare.');
   }catch(error){if(user?.id===uid)report(error.message||'Salvataggio non riuscito.',true);}
   finally{button.disabled=false;}
 });
 byId('notifications-push-disable').addEventListener('click',async()=>{
   if(!user)return;
   const uid=user.id,button=byId('notifications-push-disable');button.disabled=true;
   try{await revokeDevicePush(client);if(user?.id===uid)report('Push disattivate su questo dispositivo.');}
   catch(error){if(user?.id===uid)report(error.message,true);}
   finally{button.disabled=false;}
 });

 toggle.addEventListener('click',()=>{
   if(!user)return;
   if(!dialog.open)dialog.showModal();
   void loadPreferences();
   void load();
 });
 byId('notifications-close').addEventListener('click',()=>dialog.close());
 byId('notifications-refresh').addEventListener('click',()=>{void load();void loadPreferences();});
 byId('notifications-push').addEventListener('click',async()=>{
   const button=byId('notifications-push');button.disabled=true;
   try{report(await subscribeBackground());}
   catch(error){report(error.message||'Registrazione push fallita.',true);}
   finally{button.disabled=false;}
 });
  permission.addEventListener('click',async()=>{
   if(!('Notification' in window)){report('Il browser non supporta le notifiche di sistema.',true);return;}
   if(!window.isSecureContext){report('Le notifiche richiedono HTTPS.',true);return;}
   const status=await Notification.requestPermission();
   report(status==='granted'
    ?'Permesso concesso. Gli avvisi del browser seguono le preferenze; per le push ad app chiusa usa il pulsante dedicato.'
    :'Permesso notifiche non concesso: gli avvisi in-app rimangono disponibili.',status!=='granted');
 });
 document.addEventListener('visibilitychange',()=>{
   if(document.visibilityState==='visible'&&user)void load();
 });
 client.auth.onAuthStateChange((_e,s)=>queueMicrotask(()=>session(s?.user||null)));
 client.auth.getUser().then(({data,error})=>{if(!error)session(data?.user||null);});
}
