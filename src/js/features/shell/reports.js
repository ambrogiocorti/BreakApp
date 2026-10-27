import {workbookBytes,csvTable,pdfBytes,downloadReport} from './report-files.js';
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
    ['Rimborsi da completare EUR',selected.stripe_refunds_pending_cents/100],['Netto registrato EUR',selected.net_recorded_cents/100],
    ['Righe ordini esportate',result.rows.length],['Limite raggiunto',result.truncated?'Si, restringere il periodo':'No'],
    ['Nota','Rendiconto interno. Non sostituisce i documenti fiscali.']];
   if(kind==='xlsx')downloadReport(workbookBytes([{name:'Riepilogo',rows:summary},{name:'Ordini',rows:table}]),
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',stem+'.xlsx');
   else if(kind==='pdf')downloadReport(pdfBytes([...summary.map(r=>r.join(': ')),'',
    ...table.map(row=>row.map(v=>typeof v==='number'?v.toFixed(2):v).join(' | '))]),'application/pdf',stem+'.pdf');
   else downloadReport(csvTable(table),'text/csv;charset=utf-8',stem+'.csv');
   say(result.rows.length+' ordini esportati'+(result.truncated?'. Limite 20.000 righe raggiunto: restringi il periodo.':'.'));
  }catch(e){say(e.message||'Esportazione non riuscita.',true);}finally{button.disabled=!valid()||!report;}
 });
 const announcement=$('announcement-form');
 announcement.addEventListener('input',()=>{announcementKey=null;});
 announcement.addEventListener('submit',async event=>{
  event.preventDefault();if(!valid()||!announcement.reportValidity())return;
  if(!confirm('Inviare questo annuncio agli utenti attivi di questa scuola?'))return;
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
