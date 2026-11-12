// Registro degli scontrini da emettere: ogni incasso o rimborso dell'app crea una
// riga sul server; il bar la segna come emessa con il proprio registratore.
import {csvTable,downloadReport} from './report-files.js';
const $=id=>document.getElementById(id);
const money=c=>new Intl.NumberFormat('it-IT',{style:'currency',currency:'EUR'}).format(Number(c)/100);
const when=t=>new Intl.DateTimeFormat('it-IT',{timeZone:'Europe/Rome',day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'}).format(new Date(t));
const el=(tag,text='',cls='')=>{const n=document.createElement(tag);n.textContent=text;if(cls)n.className=cls;return n;};

export const FISCAL_METHODS={card:'Carta online',cash:'Contanti',external_pos:'POS del bar'};
export const fiscalTypeLabel=d=>d.doc_type==='return'?'Reso':'Vendita';
export const fiscalLinesText=lines=>(lines||[]).map(l=>`${l.quantity}× ${l.name}`).join(', ');
export function fiscalSummary(docs){
  const open=docs.filter(d=>d.status==='to_issue');
  const sum=t=>open.filter(d=>d.doc_type===t).reduce((a,d)=>a+Number(d.amount_cents),0);
  return {count:open.length,sales_cents:sum('sale'),returns_cents:sum('return')};
}
export const fiscalTable=docs=>[
  ['Data','Ordine','Tipo','Metodo','Importo EUR','Totale ordine EUR','Prodotti','Stato'],
  ...docs.map(d=>[d.created_at,d.reference,fiscalTypeLabel(d),FISCAL_METHODS[d.payment_method]||d.payment_method,
    Number(d.amount_cents)/100,Number(d.order_total_cents)/100,fiscalLinesText(d.lines),d.status==='issued'?'Emesso':'Da emettere'])];

export function initializeFiscalDocuments(client){
  if(!client)return;
  const panel=$('fiscal-documents'),list=$('fiscal-list'),summary=$('fiscal-summary'),
    status=$('fiscal-status'),exportButton=$('fiscal-export');
  let ctx=null,docs=[],epoch=0;
  const valid=()=>ctx?.role==='school_admin'&&ctx.verified&&ctx.schoolId;
  const say=(text,error=false)=>{summary.textContent=text;summary.dataset.type=error?'error':'information';};
  function draw(){
    list.replaceChildren();
    if(!docs.length){list.append(el('p','Nessuno scontrino in questo periodo.','help'));return;}
    for(const d of docs){
      const row=el('article','','fiscal-row'+(d.doc_type==='return'?' is-return':''));
      const text=el('div','','fiscal-text');
      text.append(el('strong',`${fiscalTypeLabel(d)} ${money(d.amount_cents)} · ${FISCAL_METHODS[d.payment_method]||''}`),
        el('span',`${when(d.created_at)} · ordine ${d.reference}`+(Number(d.amount_cents)!==Number(d.order_total_cents)?` (totale ordine ${money(d.order_total_cents)})`:''),'fiscal-meta'),
        el('span',fiscalLinesText(d.lines)||'Prodotti non disponibili','fiscal-meta'));
      const button=el('button',d.status==='issued'?'Riapri':'Segna emesso',
        'button button-small '+(d.status==='issued'?'button-ghost':'button-primary'));
      button.type='button';
      button.addEventListener('click',async()=>{
        button.disabled=true;
        const {error}=await client.rpc('mark_fiscal_document',{p_id:d.id,p_issued:d.status!=='issued'});
        if(error){say(error.message,true);button.disabled=false;return;}
        await load();
      });
      row.append(text,button);list.append(row);
    }
  }
  async function load(){
    if(!valid())return;
    const token=++epoch,school=ctx.schoolId;
    exportButton.disabled=true;say('Caricamento degli scontrini…');
    const {data,error}=await client.rpc('list_fiscal_documents',{p_school:school,
      p_from:$('reports-from').value,p_to:$('reports-to').value,p_status:status.value||null});
    if(token!==epoch||school!==ctx?.schoolId)return;
    if(error){docs=[];draw();say(error.message,true);return;}
    docs=Array.isArray(data)?data:[];draw();exportButton.disabled=!docs.length;
    const s=fiscalSummary(docs);
    say(s.count?`${s.count} da emettere: vendite ${money(s.sales_cents)}, resi ${money(s.returns_cents)}.`:'Nessuno scontrino da emettere in questo periodo.');
  }
  $('fiscal-refresh').addEventListener('click',()=>{void load();});
  status.addEventListener('change',()=>{void load();});
  $('reports-form').addEventListener('submit',()=>{void load();});
  exportButton.addEventListener('click',()=>{
    if(!docs.length)return;
    downloadReport(csvTable(fiscalTable(docs)),'text/csv;charset=utf-8',
      `breakapp-scontrini-${$('reports-from').value}_${$('reports-to').value}.csv`);
  });
  window.addEventListener('breakapp:workspace-context',event=>{
    epoch++;ctx=event.detail;docs=[];list.replaceChildren();summary.textContent='';exportButton.disabled=true;
    panel.hidden=!valid();
    // Le date del report vengono impostate dallo stesso evento: carica subito dopo.
    if(valid())queueMicrotask(()=>{void load();});
  });
  client.auth.onAuthStateChange((_e,session)=>{if(!session){epoch++;ctx=null;docs=[];list.replaceChildren();panel.hidden=true;}});
}
