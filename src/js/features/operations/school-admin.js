import {readClassNames} from './class-import.js';
import {renderSchoolStaffPanel} from './school-staff.js';
import {formatEuro} from '../catalog/utils.js';
import {confirmDialog} from '../../core/dialog.js';
import {hideWhenSingleChoice} from '../../core/single-choice.js';

// Strumenti dell'Admin scuola che prima stavano in fondo a «Richieste»:
//  * Personale: una voce di menu propria;
//  * Promozioni: coupon e bundle, una voce di menu propria;
//  * Regole della scuola (limite richieste, mancati ritiri, classi): un
//    pannello dentro «Impostazioni».
// Le autorizzazioni restano sul server: ogni RPC verifica Admin, scuola e 2FA.

const el=(tag,text='',cls='')=>{const x=document.createElement(tag);x.textContent=text;if(cls)x.className=cls;return x;};
let fieldSeq=0;
function field(form,label,{type='text',value='',required=true,optional='',wide=false}={}){
 const box=el('div','',wide?'field field-wide':'field'),lab=el('label',label),input=el('input');
 input.id='school-admin-field-'+(++fieldSeq);lab.htmlFor=input.id;input.type=type;input.value=value;input.required=required;
 if(optional)lab.append(' ',el('span',optional,'optional'));
 box.append(lab,input);form.append(box);return input;
}
function choice(form,label,rows,{wide=false}={}){
 const box=el('div','',wide?'field field-wide':'field'),lab=el('label',label),select=el('select');
 select.id='school-admin-field-'+(++fieldSeq);lab.htmlFor=select.id;
 for(const [value,text] of rows)select.add(new Option(text,value));
 box.append(lab,select);form.append(box);return select;
}
function submitRow(form,label){
 const wrap=el('div','','field-wide'),b=el('button',label,'button button-primary');b.type='submit';wrap.append(b);form.append(wrap);return b;
}
function panel(parent,title,help){
 const box=el('section','','panel'),head=el('div','','panel-head');head.append(el('h2',title));box.append(head);
 if(help)box.append(el('p',help,'help'));parent.append(box);return box;
}
// Euro scritti dall'Admin (anche con la virgola) in centesimi interi.
export function euroToCents(text){
 const value=Number(String(text??'').trim().replace(',','.'));
 if(!Number.isFinite(value)||value<0)return NaN;
 return Math.round(value*100);
}
export const PROMOTION_KINDS=Object.freeze([
 ['percent','Sconto percentuale'],
 ['unit_discount','Sconto fisso per prodotto'],
 ['bundle','Bundle di prodotti']
]);
// Valore inviato al server: percentuale intera o centesimi.
export function promotionValue(kind,text){
 if(kind==='percent'){const n=Number(String(text).replace(',','.'));return Number.isInteger(n)?n:NaN;}
 return euroToCents(text);
}

export function initializeSchoolAdmin(client){
 if(!client)return;
 const staffSection=document.getElementById('school-staff'),staffRoot=document.getElementById('school-staff-root');
 const promoSection=document.getElementById('school-promotions'),promoRoot=document.getElementById('school-promotions-root');
 const promoStatus=document.getElementById('school-promotions-status');
 const settingsPanel=document.getElementById('school-settings-panel'),settingsRoot=document.getElementById('school-settings-root');
 const settingsStatus=document.getElementById('school-settings-status');
 if(!staffSection||!promoSection||!settingsPanel)return;
 let context=null,epoch=0;
 const say=(node,text,error=false)=>{node.textContent=text;node.dataset.type=error?'error':'success';};
 async function rpc(name,args){const r=await client.rpc(name,args);if(r.error)throw r.error;return r.data;}
 async function guarded(button,status,fn,done){
  button.disabled=true;
  // fn può restituire false (annullato) o un messaggio proprio.
  try{const r=await fn();if(r!==false)say(status,typeof r==='string'?r:done);}
  catch(e){say(status,e?.message||'Operazione non riuscita.',true);}
  finally{button.disabled=false;}
 }
 function hideAll(){
  epoch++;staffSection.hidden=true;promoSection.hidden=true;settingsPanel.hidden=true;
  staffRoot.replaceChildren();promoRoot.replaceChildren();settingsRoot.replaceChildren();
  promoStatus.textContent='';settingsStatus.textContent='';
 }

 function renderStaff(){
  staffRoot.replaceChildren();
  renderSchoolStaffPanel(staffRoot,{client,schoolId:context.schoolId});
 }

 async function renderSettings(v){
  settingsRoot.replaceChildren();
  const r=await client.from('schools').select('max_active_approvals,no_show_penalty_minutes,require_guest_class').eq('id',context.schoolId);
  if(v!==epoch)return;
  if(r.error)throw r.error;
  const s=r.data?.[0]||{};
  const form=el('form','','form-grid');
  form.append(el('p','Con 0 minuti un mancato ritiro non blocca nuove prenotazioni.','help field-wide'));
  const limit=field(form,'Grandi ordini in valutazione insieme',{type:'number',value:String(s.max_active_approvals??3)});limit.min='1';limit.max='30';
  const minutes=field(form,'Blocco dopo un mancato ritiro (min)',{type:'number',value:String(s.no_show_penalty_minutes||0)});minutes.min='0';minutes.max='10080';
  const requireClass=choice(form,'Classe degli ospiti',[['false','Facoltativa'],['true','Obbligatoria, tra le classi importate']],{wide:true});
  requireClass.value=String(Boolean(s.require_guest_class));
  const save=submitRow(form,'Salva regole della scuola');
  form.addEventListener('submit',e=>{e.preventDefault();if(!form.reportValidity())return;
   void guarded(save,settingsStatus,async()=>{
    await rpc('set_approval_capacity',{p_school:context.schoolId,p_limit:Number(limit.value)});
    await rpc('set_no_show_policy',{p_school:context.schoolId,p_minutes:Number(minutes.value)});
    await rpc('set_guest_class_policy',{p_school:context.schoolId,p_required:requireClass.value==='true'});
   },'Regole salvate.');
  });
  const classes=el('form','','form-grid school-settings-classes');
  classes.append(el('h3','Classi','field-wide'),el('p','Servono per la classe degli ospiti. Le classi già presenti non vengono duplicate.','help field-wide'));
  const file=field(classes,'File CSV o Excel con l’elenco delle classi',{type:'file',wide:true});file.accept='.csv,.xlsx';
  const importButton=submitRow(classes,'Importa classi');
  classes.addEventListener('submit',e=>{e.preventDefault();if(!classes.reportValidity())return;
   void guarded(importButton,settingsStatus,async()=>{
    const n=await rpc('import_school_classes',{p_school:context.schoolId,p_names:await readClassNames(file.files[0])});
    file.value='';return 'Classi importate: '+n+'.';
   },'Classi importate.');
  });
  settingsRoot.append(form,classes);
 }

 async function renderPromotions(v){
  promoRoot.replaceChildren();
  const [bars,products]=await Promise.all([
   client.from('bars').select('id,name').eq('school_id',context.schoolId).eq('is_active',true),
   client.from('products').select('id,name').eq('school_id',context.schoolId).eq('is_active',true)
  ]);
  if(v!==epoch)return;
  if(bars.error)throw bars.error;if(products.error)throw products.error;
  const barRows=(bars.data||[]).map(b=>[b.id,b.name]),productRows=(products.data||[]).map(p=>[p.id,p.name]);
  if(!barRows.length){promoRoot.append(el('p','Nessun bar attivo in questa scuola.','empty-state'));return;}
  const grid=el('div','','setup-grid');promoRoot.append(grid);

  const create=panel(grid,'Nuova promozione','Il cliente inserisce il codice al momento della prenotazione. Lo sconto è calcolato dal server.');
  const f=el('form','','form-grid');create.append(f);
  const bar=choice(f,'Bar',barRows),code=field(f,'Codice'),title=field(f,'Titolo');
  hideWhenSingleChoice(bar);
  code.placeholder='Es. MERENDA10';code.autocomplete='off';
  const kind=choice(f,'Tipo',PROMOTION_KINDS);
  const value=field(f,'Sconto (%)',{type:'text',value:'10'});value.inputMode='decimal';
  const start=field(f,'Inizio',{type:'datetime-local'}),end=field(f,'Fine',{type:'datetime-local'});
  const max=field(f,'Utilizzi totali',{type:'number',required:false,optional:'vuoto: nessun limite'});max.min='1';
  const per=field(f,'Utilizzi per cliente',{type:'number',value:'1'});per.min='1';
  const valueLabel=value.labels?.[0]||value.previousElementSibling;
  const recipe=[];
  const bundle=el('fieldset','','field-wide promotion-bundle');bundle.hidden=true;
  bundle.append(el('legend','Prodotti del bundle'));
  const recipeList=el('ul','','row-list');bundle.append(recipeList);
  const bundleGrid=el('div','','form-grid');bundle.append(bundleGrid);
  const component=choice(bundleGrid,'Prodotto',productRows),qty=field(bundleGrid,'Quantità',{type:'number',value:'1',required:false});qty.min='1';
  const discount=field(bundleGrid,'Sconto per pezzo (€)',{type:'text',value:'0',required:false});discount.inputMode='decimal';
  const addWrap=el('div','','field-wide'),add=el('button','Aggiungi al bundle','button button-outline button-small');add.type='button';addWrap.append(add);bundleGrid.append(addWrap);
  f.append(bundle);
  const save=submitRow(f,'Crea promozione');
  const syncKind=()=>{
   const isPercent=kind.value==='percent',isBundle=kind.value==='bundle';
   if(valueLabel)valueLabel.textContent=isPercent?'Sconto (%)':isBundle?'Sconto sul bundle (€)':'Sconto per prodotto (€)';
   bundle.hidden=!isBundle;
  };
  kind.addEventListener('change',syncKind);syncKind();
  const drawRecipe=()=>{recipeList.replaceChildren();
   for(const [i,r] of recipe.entries()){
    const row=el('li','','row');row.append(el('span',r.quantity+' × '+(productRows.find(p=>p[0]===r.product_id)?.[1]||'Prodotto')+(r.discount_cents?' · −'+formatEuro(r.discount_cents)+' a pezzo':'')));
    const remove=el('button','Togli','button button-ghost button-small');remove.type='button';
    remove.setAttribute('aria-label','Togli '+(productRows.find(p=>p[0]===r.product_id)?.[1]||'prodotto')+' dal bundle');
    remove.addEventListener('click',()=>{recipe.splice(i,1);drawRecipe();});row.append(remove);recipeList.append(row);
   }
   if(!recipe.length)recipeList.append(el('li','Nessun prodotto aggiunto.','help'));
  };
  drawRecipe();
  add.addEventListener('click',()=>{
   const cents=euroToCents(discount.value),q=Number(qty.value);
   if(!component.value||!Number.isInteger(q)||q<1||Number.isNaN(cents)){say(promoStatus,'Controlla prodotto, quantità e sconto del bundle.',true);return;}
   recipe.push({product_id:component.value,quantity:q,discount_cents:cents});drawRecipe();
  });
  f.addEventListener('submit',e=>{e.preventDefault();if(!f.reportValidity())return;
   const amount=promotionValue(kind.value,value.value);
   if(Number.isNaN(amount)){say(promoStatus,kind.value==='percent'?'Lo sconto percentuale è un numero intero.':'Scrivi lo sconto in euro, per esempio 0,50.',true);return;}
   if(kind.value==='bundle'&&!recipe.length){say(promoStatus,'Aggiungi almeno un prodotto al bundle.',true);return;}
   void guarded(save,promoStatus,async()=>{
    await rpc('save_school_promotion',{p_id:null,p_bar:bar.value,p_code:code.value,p_title:title.value,p_kind:kind.value,p_value:amount,
     p_start:new Date(start.value).toISOString(),p_end:new Date(end.value).toISOString(),p_max:max.value?Number(max.value):null,
     p_per_user:Number(per.value),p_recipe:kind.value==='bundle'?recipe:[]});
    await drawActive(bar.value,v);
   },'Promozione creata.');
  });

  const activePanel=panel(grid,'Promozioni attive');
  const activeBar=barRows.length>1?choice(activePanel,'Bar',barRows):null;
  const list=el('div','','row-list');activePanel.append(list);
  async function drawActive(barId,version){
   const promos=await rpc('list_school_promotions',{p_bar:barId});
   if(version!==epoch)return;
   list.replaceChildren();
   if(!(promos||[]).length){list.append(el('p','Nessuna promozione attiva.','help'));return;}
   for(const p of promos){
    const row=el('div','','row'),info=el('div','','row-main');
    info.append(el('strong',p.code),el('span',p.title+' · fino al '+new Date(p.ends_at).toLocaleDateString('it-IT')));
    const off=el('button','Disattiva','button button-outline button-small');off.type='button';off.setAttribute('aria-label','Disattiva '+p.code);
    off.addEventListener('click',()=>void guarded(off,promoStatus,async()=>{
     if(!await confirmDialog('Disattivare la promozione '+p.code+'?'))return false;
     await rpc('save_school_promotion',{p_id:p.id,p_bar:barId,p_code:p.code,p_title:p.title,p_kind:p.kind,p_value:p.value,p_start:new Date().toISOString(),p_end:p.ends_at,p_max:null,p_per_user:1,p_recipe:[]});
     await drawActive(barId,version);
    },'Promozione disattivata.'));
    row.append(info,off);list.append(row);
   }
  }
  activeBar?.addEventListener('change',()=>void drawActive(activeBar.value,epoch).catch(e=>say(promoStatus,e.message,true)));
  await drawActive(activeBar?.value||barRows[0][0],v);
 }

 async function render(){
  const v=++epoch;
  const admin=context?.verified&&context.role==='school_admin'&&context.schoolId;
  staffSection.hidden=!admin;promoSection.hidden=!admin;settingsPanel.hidden=!admin;
  if(!admin){hideAll();return;}
  renderStaff();
  await Promise.all([
   renderSettings(v).catch(e=>{if(v===epoch)say(settingsStatus,'Impossibile caricare le regole: '+e.message,true);}),
   renderPromotions(v).catch(e=>{if(v===epoch)say(promoStatus,'Impossibile caricare le promozioni: '+e.message,true);})
  ]);
 }
 window.addEventListener('breakapp:workspace-context',e=>{context=e.detail;void render();});
 client.auth.onAuthStateChange((_e,session)=>queueMicrotask(()=>{if(!session?.user){context=null;hideAll();}}));
}
