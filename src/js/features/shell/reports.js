import {confirmDialog,promptDialog} from '../../core/dialog.js';
import {workbookBytes,csvTable,reportPdfBytes,downloadReport} from './report-files.js';
import {orderStatusLabel} from '../orders/staff-board.js';
const $=id=>document.getElementById(id);
const money=c=>new Intl.NumberFormat('it-IT',{style:'currency',currency:'EUR'}).format(Number(c)/100);
const el=(tag,text='',cls='')=>{const n=document.createElement(tag);n.textContent=text;n.className=cls;return n;};
export async function loadReportRows(client,school,from,to,maxRows=20000){
 const rows=[];for(let offset=0;offset<maxRows;offset+=500){
  const {data,error}=await client.rpc('school_order_report_rows',{
   p_school:school,p_from:from,p_to:to,p_offset:offset,p_limit:Math.min(500,maxRows-offset)});
  if(error)throw error;if(!Array.isArray(data))throw Error('Report non valido');
  rows.push(...data);if(data.length<500)return {rows,truncated:false};
 }return {rows,truncated:true};
}
export const reportTable=rows=>[
 ['Ordine','Tipo','Bar','Creato il','Giorno ritiro','Fascia','Stato','Totale EUR','Residuo EUR'],
 ...rows.map(r=>[r.reference,r.kind==='group'?'Gruppo':'Individuale',r.bar,r.created_at,
  r.service_date,r.starts_at,r.status,Number(r.total_cents)/100,Number(r.due_cents)/100])];
const itDate=d=>{const m=/^(\d{4})-(\d{2})-(\d{2})/.exec(String(d||''));return m?`${m[3]}/${m[2]}/${m[1]}`:String(d||'');};
const itDateTime=t=>{const d=new Date(t);return Number.isNaN(d.getTime())?String(t||''):new Intl.DateTimeFormat('it-IT',{timeZone:'Europe/Rome',day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'}).format(d);};
const hhmm=t=>String(t||'').slice(0,5);
// Documento del PDF: riepilogo degli incassi, prodotti venduti ed elenco ordini.
export function reportPdfDocument(selected,result){
 const c=k=>money(selected[k]||0);
 return {
  title:'Report incassi',subtitle:selected.school_name||'',
  meta:[['Periodo',itDate(selected.from)+' - '+itDate(selected.to)],['Generato il',itDateTime(new Date().toISOString())],
   ['Ordini',(selected.individual_orders??0)+' individuali, '+(selected.group_orders??0)+' di gruppo, '+(selected.counter_sales??0)+' vendite al banco']],
  sections:[
   {title:'Riepilogo',kind:'kv',rows:[['Contanti registrati',c('cash_cents')],['POS del bar',c('external_pos_cents')],
    ['Pagamenti online (Stripe, lordo)',c('stripe_gross_cents')],['Rimborsi online confermati','- '+c('stripe_refunded_cents')],
    ['Contanti restituiti','- '+c('cash_returned_cents')],['Rimborsi online da completare',c('stripe_refunds_pending_cents')],
    ['Contanti ancora da restituire',c('cash_refunds_pending_cents')],['Incassi netti registrati',c('net_recorded_cents'),true]]},
   {title:'Prodotti venduti',kind:'table',empty:'Nessun prodotto venduto nel periodo.',
    columns:[{label:'Prodotto',w:300},{label:'Quantità',w:90,align:'right'},{label:'Importo',w:120,align:'right'}],
    rows:(selected.products||[]).map(p=>[p.name,String(p.quantity),money(p.amount_cents)])},
   {title:'Ordini',kind:'table',empty:'Nessun ordine nel periodo.',
    note:result.truncated?'Elenco troncato a 20.000 ordini: restringi il periodo per vederli tutti.':'',
    columns:[{label:'Ordine',w:52},{label:'Tipo',w:58},{label:'Creato il',w:88},{label:'Ritiro',w:92},{label:'Stato',w:80},{label:'Totale',w:62,align:'right'},{label:'Da incassare',w:68,align:'right'}],
    rows:result.rows.map(r=>[r.reference,r.kind==='group'?'Gruppo':'Individuale',itDateTime(r.created_at),
     (r.service_date?itDate(r.service_date):'')+(r.starts_at?' '+hhmm(r.starts_at):''),orderStatusLabel(r.status)||r.status,
     money(r.total_cents||0),Number(r.due_cents)?money(r.due_cents):'-'])}],
  footer:'BreakApp - rendiconto interno, non sostituisce i documenti fiscali.'
 };
}
export function initializeReports(client){
 if(!client)return;
 const panel=$('school-reports'),feedback=$('reports-feedback'),form=$('reports-form');
 let ctx=null,report=null,epoch=0,announcementKey=null;
 const say=(text,error=false)=>{feedback.textContent=text;feedback.dataset.type=error?'error':'information';};
 const valid=()=>ctx?.role==='school_admin'&&ctx.verified&&ctx.schoolId;
 function draw(){
  const grid=$('reports-metrics');grid.replaceChildren();
  const labels=[['cash_cents','Contanti registrati'],['external_pos_cents','POS esterno registrato'],
   ['stripe_gross_cents','Stripe incassato'],['stripe_refunded_cents','Rimborsi Stripe confermati'],
   ['cash_returned_cents','Contanti restituiti'],['cash_refunds_pending_cents','Contanti ancora da restituire'],
   ['stripe_refunds_pending_cents','Rimborsi da completare / verificare'],['net_recorded_cents','Incassi netti registrati']];
  for(const [key,label] of labels){const box=el('article','','metric-card');box.append(el('p',label),el('strong',money(report[key])));grid.append(box);}
  $('reports-order-count').textContent=report.individual_orders+' ordini individuali · '+report.group_orders+
   ' ordini di gruppo · '+report.counter_sales+' vendite al banco · '+report.open_stock_conflicts+' conflitti scorte aperti';
  const products=$('reports-products');products.replaceChildren();
  for(const item of report.products||[])products.append(el('p',item.name+' · '+item.quantity+' unità · '+money(item.amount_cents)));
  for(const button of panel.querySelectorAll('[data-export]'))button.disabled=false;
 }
 form.addEventListener('submit',async event=>{
  event.preventDefault();if(!valid()||!form.reportValidity())return;
  const token=++epoch,school=ctx.schoolId;report=null;
  for(const b of panel.querySelectorAll('[data-export]'))b.disabled=true;
  say('Calcolo dei movimenti della scuola…');
  const {data,error}=await client.rpc('school_financial_report',{p_school:school,
   p_from:$('reports-from').value,p_to:$('reports-to').value});
  if(token!==epoch||school!==ctx?.schoolId)return;
  if(error){say(error.message,true);return;}report=data;draw();say('Report aggiornato. Importi registrati nel periodo selezionato.');
 });
 for(const button of panel.querySelectorAll('[data-export]'))button.addEventListener('click',async()=>{
  if(!valid()||!report)return;
  const token=epoch,school=ctx.schoolId,selected=structuredClone(report),kind=button.dataset.export;
  button.disabled=true;say('Preparazione del file…');
  try{
   const result=await loadReportRows(client,school,selected.from,selected.to);
   if(!valid()||epoch!==token||ctx.schoolId!==school)return;
   const table=reportTable(result.rows),stem='breakapp-report-'+selected.from+'_'+selected.to;
   const summary=[['BreakApp',selected.school_name],['Periodo',selected.from+' / '+selected.to],
    ['Contanti EUR',selected.cash_cents/100],['POS esterno EUR',selected.external_pos_cents/100],
    ['Stripe lordo EUR',selected.stripe_gross_cents/100],['Rimborsi confermati EUR',selected.stripe_refunded_cents/100],
    ['Rimborsi da completare EUR',selected.stripe_refunds_pending_cents/100],['Contanti restituiti EUR',(selected.cash_returned_cents||0)/100],['Contanti da restituire EUR',(selected.cash_refunds_pending_cents||0)/100],['Netto registrato EUR',selected.net_recorded_cents/100],
    ['Righe ordini esportate',result.rows.length],['Limite raggiunto',result.truncated?'Si, restringere il periodo':'No'],
    ['Nota','Rendiconto interno. Non sostituisce i documenti fiscali.']];
   if(kind==='xlsx')downloadReport(workbookBytes([{name:'Riepilogo',rows:summary},{name:'Ordini',rows:table}]),
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',stem+'.xlsx');
   else if(kind==='pdf')downloadReport(reportPdfBytes(reportPdfDocument(selected,result)),'application/pdf',stem+'.pdf');
   else downloadReport(csvTable(table),'text/csv;charset=utf-8',stem+'.csv');
   say(result.rows.length+' ordini esportati'+(result.truncated?'. Limite 20.000 righe raggiunto: restringi il periodo.':'.'));
  }catch(e){say(e.message||'Esportazione non riuscita.',true);}finally{button.disabled=!valid()||!report;}
 });
 const announcement=$('announcement-form');
 announcement.addEventListener('input',()=>{announcementKey=null;});
 announcement.addEventListener('submit',async event=>{
  event.preventDefault();if(!valid()||!announcement.reportValidity())return;
  if(!await confirmDialog('Inviare questo annuncio agli utenti attivi di questa scuola?'))return;
  const token=epoch,school=ctx.schoolId,button=announcement.querySelector('button');button.disabled=true;
  announcementKey||=crypto.randomUUID();
  const {error}=await client.rpc('publish_school_announcement',{p_school:school,
   p_title:$('announcement-title').value.trim(),p_body:$('announcement-body').value.trim(),p_key:announcementKey});
  if(token!==epoch||school!==ctx?.schoolId){button.disabled=false;return;}
  if(error)say(error.message,true);else{announcement.reset();announcementKey=null;say('Annuncio pubblicato nel centro notifiche della scuola.');}
  button.disabled=false;
 });
 window.addEventListener('breakapp:workspace-context',event=>{
  epoch++;ctx=event.detail;report=null;announcementKey=null;panel.hidden=!valid();
  $('reports-metrics').replaceChildren();$('reports-products').replaceChildren();$('reports-order-count').textContent='';
  for(const b of panel.querySelectorAll('[data-export]'))b.disabled=true;
  const today=new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Rome'}).format(new Date());
  $('reports-from').value=today.slice(0,8)+'01';$('reports-to').value=today;
 });
 client.auth.onAuthStateChange((_e,session)=>{if(!session){epoch++;ctx=null;report=null;panel.hidden=true;
  $('reports-metrics').replaceChildren();$('reports-products').replaceChildren();}});
}
